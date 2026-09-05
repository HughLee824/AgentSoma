import Foundation

struct AXNode {
    let index: Int
    let parent: Int?
    let role: String
    let attributes: [String: Any]

    var label: String { attributes["label"] as? String ?? "" }
    var identifier: String { attributes["identifier"] as? String ?? "" }
    var enabled: Bool { attributes["enabled"] as? Bool ?? true }
    var value: Any? {
        guard let value = attributes["value"], !(value is NSNull), (value as? String) != "" else { return nil }
        return value
    }
    var ref: String { "e\(index + 1)" }
}

// Device facts only. Backend-specific element types are translated by the adapter.
struct CapturedObservation {
    let nodes: [AXNode]
    let metadata: [String: Any]
    let screenshot: Data
}

struct ObservationReference {
    let observation: String
    let node: Int?

    init(_ value: String) throws {
        guard value.range(of: "^o[1-9][0-9]*(?::e[1-9][0-9]*)?$", options: .regularExpression) != nil else {
            throw SomaError("invalid_reference", "Use an observation or element reference, such as o1 or o1:e2")
        }
        let parts = value.split(separator: ":")
        observation = String(parts[0])
        if parts.count == 2 {
            guard let number = Int(parts[1].dropFirst()) else { throw SomaError("invalid_reference", "Element number is too large") }
            node = number - 1
        } else { node = nil }
    }
}

// Accessed only on the host's serial work queue. No device calls are made by inspect.
final class ObservationCache {
    private struct Entry {
        let id: String
        let capture: CapturedObservation
        let directory: URL
        var validity: String
    }
    private let directory: URL
    private var entries: [Entry] = []
    private var nextID = 1
    private(set) var currentID: String?

    init(directory: URL) { self.directory = directory.appendingPathComponent("observations") }

    func invalidate(_ reason: String) {
        if let index = entries.firstIndex(where: { $0.id == currentID }) { entries[index].validity = reason }
        currentID = nil
    }

    func beginAction() -> String? {
        let previous = currentID
        invalidate("action_pending")
        return previous
    }

    func finishAction(previous: String?, dispatched: Bool) {
        guard let index = entries.firstIndex(where: { $0.id == previous }) else { return }
        entries[index].validity = dispatched ? "invalidated" : "current"
        if !dispatched { currentID = previous }
    }

    func store(_ capture: CapturedObservation) throws -> [String: Any] {
        let id = "o\(nextID)"
        nextID += 1
        let location = directory.appendingPathComponent(id)
        try SessionPaths.secureDirectory(directory)
        try SessionPaths.secureDirectory(location)
        do {
            try capture.screenshot.write(to: location.appendingPathComponent("screen.png"), options: .atomic)
            let nodes = capture.nodes.map { node -> [String: Any] in
                var attributes = node.attributes
                attributes["ref"] = "\(id):\(node.ref)"
                attributes["role"] = node.role
                return attributes
            }
            try saveJSON(["observation": id, "metadata": capture.metadata, "nodes": nodes],
                         to: location.appendingPathComponent("snapshot.json"))
            for file in ["screen.png", "snapshot.json"] {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.appendingPathComponent(file).path)
            }
        } catch {
            try? FileManager.default.removeItem(at: location)
            throw error
        }
        invalidate("superseded")
        entries.append(Entry(id: id, capture: capture, directory: location, validity: "current"))
        currentID = id
        if entries.count > 2 {
            try FileManager.default.removeItem(at: entries[0].directory)
            entries.removeFirst()
        }
        return result(entries.last!, detail: nil)
    }

    func inspect(_ reference: ObservationReference, offset: Int) throws -> [String: Any] {
        guard let entry = entries.first(where: { $0.id == reference.observation }) else {
            throw SomaError("observation_unavailable", "Snapshot is no longer cached; observe again for new data")
        }
        if let node = reference.node, !entry.capture.nodes.indices.contains(node) {
            throw SomaError("node_not_captured", "This node was not captured; inspect cannot fetch missing source data")
        }
        let indices = subtree(entry.capture.nodes, root: reference.node)
        guard offset >= 0, offset < indices.count || (offset == 0 && indices.isEmpty) else {
            throw SomaError("invalid_offset", "Offset must address a node in this cached subtree")
        }
        return result(entry, detail: (reference, indices, offset))
    }

    // A current reference is only a candidate: the backend must validate it on the live device.
    func resolveCurrent(_ reference: ObservationReference) throws -> AXNode {
        guard let entry = entries.first(where: { $0.id == reference.observation }), currentID == entry.id else {
            throw SomaError("stale_reference", "Observe again before using this reference for an action")
        }
        guard let index = reference.node, entry.capture.nodes.indices.contains(index) else {
            throw SomaError("node_not_captured", "An element captured in this observation is required")
        }
        return entry.capture.nodes[index]
    }

    func resolveTarget(for action: DeviceAction) throws -> ObservedTarget {
        let reference = action.reference
        guard let entry = entries.first(where: { $0.id == reference.observation }), currentID == entry.id else {
            throw SomaError("stale_reference", "Observe again before using this reference for an action")
        }
        guard let scope = entry.capture.metadata["scope"] as? String, ["app", "appAlert", "systemAlert"].contains(scope),
              !entry.capture.nodes.isEmpty else { throw SomaError("target_context_unknown", "Observe a known app or alert before acting") }
        var index = 0
        if !action.coordinate {
            let node = try resolveCurrent(reference)
            if ["type", "press"].contains(action.kind), !["text_field", "secure_text_field", "text_view", "search_field"].contains(node.role) {
                throw SomaError("not_text_input", "The reference must identify a text input")
            }
            index = node.index
        }
        var path: [[String: Any]] = []
        while true {
            let node = entry.capture.nodes[index]
            var step = node.attributes
            step.removeValue(forKey: "index"); step.removeValue(forKey: "parent")
            step["childIndex"] = node.parent.map { parent in entry.capture.nodes[..<index].filter { $0.parent == parent }.count } ?? 0
            path.insert(step, at: 0)
            guard let parent = node.parent else { break }
            index = parent
        }
        return ObservedTarget(context: entry.capture.metadata, path: path)
    }

    func clear() throws {
        invalidate("session_closed")
        entries.removeAll()
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func subtree(_ nodes: [AXNode], root: Int?) -> [Int] {
        guard let root else { return Array(nodes.indices) }
        var included: Set<Int> = [root]
        for node in nodes where node.parent.map({ included.contains($0) }) == true { included.insert(node.index) }
        return nodes.indices.filter { included.contains($0) }
    }

    private func result(_ entry: Entry, detail: (ObservationReference, [Int], Int)?) -> [String: Any] {
        let capture = entry.capture
        let metadata = capture.metadata
        let screenshot = entry.directory.appendingPathComponent("screen.png").path
        let snapshot = entry.directory.appendingPathComponent("snapshot.json").path
        var lines = ["observation=\(entry.id) refs=\(entry.validity) scope=\(metadata["scope"] ?? "unknown") target=\(quoted(metadata["targetBundleId"] ?? NSNull())) foreground=\(quoted(metadata["foregroundBundleId"] ?? NSNull()))",
            "screenshot=\(quoted(screenshot)) pixels=\(metadata["screenshotWidth"] ?? "?")x\(metadata["screenshotHeight"] ?? "?") screen_points=\(quoted(metadata["screenFrame"] ?? NSNull()))",
            "ax=\(metadata["axStatus"] ?? "unavailable") source_truncated=\(metadata["sourceTruncated"] ?? "unknown") ax_started=\(metadata["snapshotStartedAt"] ?? "unknown") ax_finished=\(metadata["snapshotFinishedAt"] ?? "unknown") screenshot_at=\(metadata["screenshotCapturedAt"] ?? "unknown")"]
        if let error = metadata["axError"] as? String {
            lines.append("ax_error=\(quoted(String(error.prefix(256))))\(error.count > 256 ? " detail_clipped=true" : "")")
        }
        let footer = "snapshot=\(quoted(snapshot)) (cached source; inspect \(entry.id) for details)"
        var body: [String] = []
        var nextOffset: Int?
        if let (reference, indices, offset) = detail {
            for (position, index) in indices.enumerated().dropFirst(offset) {
                let node = capture.nodes[index]
                var attributes = node.attributes
                attributes["ref"] = "\(entry.id):\(node.ref)"
                attributes["role"] = node.role
                var line = String(decoding: (try? jsonData(attributes)) ?? Data(), as: UTF8.self)
                if line.utf8.count > 4096 { line = "[\(node.ref)] detail_exceeds_budget; full attributes in snapshot file" }
                if body.count == 20 || !fits(lines + body + [line, footer], reserve: 400) { nextOffset = position; break }
                body.append(line)
            }
            let target = reference.node.map { "\(entry.id):e\($0 + 1)" } ?? entry.id
            lines.append("inspect=\(target) offset=\(offset) captured_nodes=\(indices.count)")
            lines += body
            if let nextOffset { lines.append("more: inspect \(target) --offset \(nextOffset) (same cached snapshot)") }
        } else {
            let compact = CompactAX.render(capture.nodes)
            var shown = 0
            for line in compact {
                if lines.count + body.count + 3 >= 60 || !fits(lines + body + [line, footer], reserve: 400) { break }
                body.append(line)
                shown += 1
            }
            lines += body
            if shown < compact.count { lines.append("unexpanded=\(compact.count - shown) lines; inspect \(entry.id) (same cached snapshot)") }
        }
        if metadata["sourceTruncated"] as? Bool == true { lines.append("source_missing=true; uncaptured nodes cannot be expanded from this snapshot") }
        lines.append(footer)
        return ["observation": entry.id, "refs": entry.validity, "screenshot": screenshot, "snapshot": snapshot,
                "text": lines.joined(separator: "\n")]
    }

    private func fits(_ lines: [String], reserve: Int) -> Bool { lines.joined(separator: "\n").utf8.count + reserve <= 8192 }
}

private func quoted(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]) else { return "null" }
    return String(decoding: data, as: UTF8.self)
}

enum CompactAX {
    static func render(_ nodes: [AXNode]) -> [String] {
        var children = Array(repeating: [Int](), count: nodes.count)
        for node in nodes { if let parent = node.parent { children[parent].append(node.index) } }
        var kept: [Int] = []
        var ancestor: [Int: Int] = [:]
        var depths: [Int: Int] = [:]
        var signatures: [Int: Set<String>] = [:]
        for node in nodes {
            let nearest = node.parent.flatMap { ancestor[$0] }
            let generic = ["group", "application", "window"].contains(node.role)
            var keep = !generic || !node.label.isEmpty || !node.identifier.isEmpty || node.value != nil || !node.enabled
            if node.role == "application" { keep = false }
            if generic, !children[node.index].isEmpty, node.enabled, node.value == nil, node.identifier.isEmpty,
               children[node.index].contains(where: { nodes[$0].label == node.label }) { keep = false }
            if let nearest, node.role == "text", node.enabled, node.label == nodes[nearest].label,
               node.value == nil || (node.value as? String) == node.label { keep = false }
            if let nearest, node.role == "web_view", nodes[nearest].role == "web_view",
               node.label.isEmpty, node.identifier.isEmpty, node.value == nil, node.enabled { keep = false }
            // Only fold identical generic container siblings, never equally named controls.
            if node.role == "group", node.identifier.isEmpty, let parent = node.parent {
                var signature = node.attributes
                signature.removeValue(forKey: "index")
                signature.removeValue(forKey: "parent")
                let key = quoted(signature)
                if signatures[parent, default: []].contains(key), children[node.index].allSatisfy({
                    nodes[$0].role == "group" && nodes[$0].label.isEmpty && nodes[$0].value == nil && nodes[$0].enabled
                }) { keep = false }
                signatures[parent, default: []].insert(key)
            }
            if keep {
                depths[node.index] = nearest.map { (depths[$0] ?? 0) + 1 } ?? 0
                ancestor[node.index] = node.index
                kept.append(node.index)
            } else { ancestor[node.index] = nearest }
        }
        let names = Dictionary(grouping: kept, by: { "\(nodes[$0].role):\(nodes[$0].label)" })
        return kept.map { index in
            let node = nodes[index]
            var clipped = false
            func brief(_ value: Any) -> String {
                let string = (value as? String) ?? quoted(value)
                if string.count > 160 { clipped = true; return quoted(String(string.prefix(160)) + "…") }
                return quoted(value)
            }
            var line = String(repeating: "  ", count: depths[index] ?? 0) + "[\(node.ref)] \(node.role)"
            if !node.label.isEmpty { line += " \(brief(node.label))" }
            let input = ["text_field", "secure_text_field", "text_view", "search_field"].contains(node.role)
            let value = input ? node.attributes["value"] : node.value
            if let value, !(value is NSNull), input || (value as? String) != node.label { line += " ax_value=\(brief(value))" }
            if !node.identifier.isEmpty, node.label.isEmpty || names["\(node.role):\(node.label)", default: []].count > 1 {
                line += " id=\(brief(node.identifier))"
            }
            if !node.enabled { line += " disabled" }
            if clipped { line += " detail_clipped=true" }
            return line
        }
    }
}
