import Foundation

struct DeviceAction {
    static let operations = ["tap", "swipe", "type"]
    let kind: String
    let reference: ObservationReference
    let fields: [String: Any]
    let coordinate: Bool

    init(operation: String, request: [String: Any]) throws {
        guard Self.operations.contains(operation) else { throw SomaError("invalid_action", "Unknown device action") }
        kind = operation
        reference = try ObservationReference(request["reference"] as? String ?? "")
        coordinate = request["x"] != nil || request["y"] != nil
        var fields: [String: Any] = ["kind": operation]
        if coordinate {
            guard operation == "tap", reference.node == nil,
                  let x = (request["x"] as? NSNumber)?.doubleValue, let y = (request["y"] as? NSNumber)?.doubleValue, x.isFinite, y.isFinite else {
                throw SomaError("invalid_coordinates", "Use tap oN --x X --y Y with finite screen point coordinates")
            }
            fields["x"] = x; fields["y"] = y
        } else if reference.node == nil {
            throw SomaError("element_required", "Use an element reference such as o1:e2")
        }
        if operation == "swipe" {
            guard let direction = request["direction"] as? String, ["up", "down", "left", "right"].contains(direction) else {
                throw SomaError("invalid_direction", "Direction must be up, down, left or right")
            }
            fields["direction"] = direction
        }
        if operation == "type" {
            guard let mode = request["mode"] as? String, ["insert", "replace"].contains(mode) else {
                throw SomaError("invalid_input_mode", "Choose --mode insert or replace")
            }
            guard let text = request["text"] as? String, text.utf8.count <= 4096,
                  mode == "replace" || !text.isEmpty,
                  text.unicodeScalars.allSatisfy({ scalar in
                      let v = scalar.value
                      return v >= 32 && v != 127 && v != 133 && v != 0x2028 && v != 0x2029 && !(0xF700...0xF8FF).contains(v)
                  }) else {
                throw SomaError("invalid_text", "Use up to 4096 UTF-8 bytes without control keys or newlines; only replace accepts empty text")
            }
            fields["mode"] = mode; fields["text"] = text
        }
        self.fields = fields
    }
}

struct ObservedTarget {
    let context: [String: Any]
    // Root through target, with each child's position within its captured parent.
    let path: [[String: Any]]
}

struct ActionFailure: Error, CustomStringConvertible {
    let code: String
    let description: String
    let possiblyExecuted: Bool
    let requiresObservation: Bool
}

enum ActionReply {
    static func decode(_ response: [String: Any]) throws -> [String: Any] {
        guard let execution = response["execution"] as? [String: Any],
              let started = execution["started"] as? Bool, let completed = execution["completed"] as? Bool else {
            throw ActionFailure(code: "missing_execution_facts", description: "Runner omitted execution facts; observe before deciding what to do next",
                                possiblyExecuted: true, requiresObservation: true)
        }
        if response["ok"] as? Bool == true, completed, started { return response["result"] as? [String: Any] ?? [:] }
        let invalidFacts = completed || response["ok"] as? Bool == true
        throw ActionFailure(code: response["errorCode"] as? String ?? "action_failed",
            description: response["error"] as? String ?? "Device action did not complete",
            possiblyExecuted: started || invalidFacts,
            requiresObservation: response["requiresObservation"] as? Bool == true || started || invalidFacts)
    }
}
