import SwiftUI
import UIKit

// Test-only harness for checking whether a longer XCTest quiescence budget can
// defer a coordinate gesture past a screen change. It is inert without its flag.
@MainActor
final class PreInputWaitProbe {
    static let shared = PreInputWaitProbe()

    private weak var animationView: UIView?
    private var didStart = false
    private var didAnimate = false
    private var events: [[String: Any]] = []
    private var onSwap: (() -> Void)?

    func arm(onSwap: @escaping () -> Void) {
        guard !didStart else { return }
        didStart = true
        self.onSwap = onSwap
        record("started")
        startAnimationIfPossible()
    }

    func attachAnimationView(_ view: UIView) {
        animationView = view
        startAnimationIfPossible()
    }

    func recordSurfaceReady(route: String) {
        record("surface_ready", route: route)
    }

    func recordRouteChanged(route: String) {
        record("route_changed", route: route)
    }

    func recordTouch(route: String, phase: String) {
        record("touch_\(phase)", route: route)
    }

    private func startAnimationIfPossible() {
        guard didStart, !didAnimate, let view = animationView else { return }
        didAnimate = true
        record("animation_started")
        UIView.animate(withDuration: 8, delay: 0, options: [.curveLinear, .beginFromCurrentState]) {
            // A one-point black view moves over the Fixture's black background. It keeps
            // UIKit animation bookkeeping active without changing the screen guard grid.
            view.transform = CGAffineTransform(translationX: 1, y: 0)
        } completion: { [weak self] _ in
            MainActor.assumeIsolated { self?.record("animation_finished") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.record("route_swap_requested")
            self.onSwap?()
        }
    }

    private func record(_ event: String, route: String? = nil) {
        var value: [String: Any] = ["event": event, "uptime": ProcessInfo.processInfo.systemUptime]
        if let route { value["route"] = route }
        events.append(value)
        save()
    }

    private func save() {
        do {
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PreInputWaitProbe.json")
            let data = try JSONSerialization.data(withJSONObject: ["events": events], options: [.sortedKeys])
            try data.write(to: file, options: .atomic)
        } catch { print("AGENTSOMA_PREINPUT_WAIT_PROBE_WRITE_FAILED \(error)") }
    }
}

struct PreInputWaitHarness: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        PreInputWaitProbe.shared.attachAnimationView(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct PreInputSwipeSurface: UIViewRepresentable {
    let route: String
    let onTouch: (String, String) -> Void

    func makeUIView(context: Context) -> PreInputSwipeSurfaceView {
        let view = PreInputSwipeSurfaceView()
        view.onTouch = onTouch
        view.route = route
        return view
    }

    func updateUIView(_ uiView: PreInputSwipeSurfaceView, context: Context) {
        uiView.onTouch = onTouch
        uiView.route = route
    }
}

final class PreInputSwipeSurfaceView: UIView {
    var onTouch: ((String, String) -> Void)?
    var route = "original" { didSet { updateAppearance() } }
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        addSubview(label)
        isAccessibilityElement = true
        accessibilityIdentifier = "preinput-surface"
        accessibilityTraits = .button
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 8, dy: 8)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouch?(route, "began")
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouch?(route, "ended")
        super.touchesEnded(touches, with: event)
    }

    private func updateAppearance() {
        let original = route == "original"
        backgroundColor = original ? .systemBlue : .systemRed
        label.text = original ? "Original swipe surface" : "Tripwire swipe surface"
        accessibilityLabel = label.text
    }
}
