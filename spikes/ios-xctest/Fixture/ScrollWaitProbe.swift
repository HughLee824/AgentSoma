import UIKit

// Opt-in test probe: no delegate replacement or changes to scroll physics.
@MainActor
final class ScrollWaitProbe {
    static let shared = ScrollWaitProbe()
    private weak var scroll: UIScrollView?
    private var timer: Timer?
    private var samples: [[String: Any]] = []
    private var lastOffset: CGPoint?
    private var wasActive = false
    private var attempts = 0
    private var ticks = 0
    private var changingFrame: UILabel?
    private var changeUntil: TimeInterval?
    private var didChangeFrames = false

    func startIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--scroll-wait-probe"), timer == nil else { return }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func findScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.bounds.height > 200 { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
    }

    private func sample() {
        ticks += 1
        guard ticks <= 12_000, samples.count < 10_000 else {
            save(); timer?.invalidate(); timer = nil
            return
        }
        if scroll == nil {
            attempts += 1
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            scroll = windows.first(where: \.isKeyWindow).flatMap { findScroll(in: $0) }
            if scroll == nil, attempts >= 100 {
                samples.append(["event": "scroll_not_found", "uptime": ProcessInfo.processInfo.systemUptime])
                save(); timer?.invalidate(); timer = nil
            }
        }
        guard let scroll else { return }
        let offset = scroll.contentOffset
        let changed = lastOffset.map { $0 != offset } ?? false
        let active = scroll.isTracking || scroll.isDragging || scroll.isDecelerating || changed
        updateChangingFrame(afterInput: active, in: scroll)
        guard active || wasActive || samples.isEmpty else { return }
        let event = active ? (wasActive ? "sample" : "active") : (wasActive ? "settled" : "ready")
        samples.append(["event": event, "uptime": ProcessInfo.processInfo.systemUptime,
                        "x": offset.x, "y": offset.y, "tracking": scroll.isTracking,
                        "dragging": scroll.isDragging, "decelerating": scroll.isDecelerating,
                        "mode": RunLoop.current.currentMode?.rawValue ?? "none"])
        let transition = active != wasActive
        lastOffset = offset
        wasActive = active
        if transition || samples.count == 1 { save() }
    }

    // Deliberately unstable pixels after the first input, only for timeout acceptance.
    // No touch interception, scroll mutation, or unbounded animation.
    private func updateChangingFrame(afterInput: Bool, in scroll: UIScrollView) {
        let now = ProcessInfo.processInfo.systemUptime
        if afterInput, !didChangeFrames,
           ProcessInfo.processInfo.arguments.contains("--unstable-after-swipe"), let window = scroll.window {
            didChangeFrames = true
            changeUntil = now + 9
            let label = UILabel(frame: CGRect(x: 20, y: 70, width: 160, height: 55))
            label.backgroundColor = .orange
            label.textColor = .black
            label.isUserInteractionEnabled = false
            window.addSubview(label)
            changingFrame = label
            samples.append(["event": "frames_changing", "uptime": now])
        }
        if let until = changeUntil {
            if now < until { changingFrame?.text = "Frame \(ticks)" }
            else {
                changingFrame?.removeFromSuperview()
                changingFrame = nil
                changeUntil = nil
                samples.append(["event": "frames_stopped", "uptime": now])
                save()
            }
        }
    }

    private func save() {
        do {
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ScrollWaitProbe.json")
            let data = try JSONSerialization.data(withJSONObject: ["pid": ProcessInfo.processInfo.processIdentifier,
                "sampleInterval": 0.05, "samples": samples], options: [.sortedKeys])
            try data.write(to: file, options: .atomic)
        } catch { print("AGENTSOMA_SCROLL_PROBE_WRITE_FAILED \(error)") }
    }
}
