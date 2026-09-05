import SwiftUI
import UIKit

@main
struct FixtureApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct ProbeView: View {
    @State private var text = ""
    @State private var count = 0
    @State private var showExtendedProbes = false
    @State private var submissions = 0
    @State private var caretPosition = -1
    @State private var mutableTitle = "Mutable A"
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("AgentSoma Probe").font(.title)
            TextField("Test text", text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($editing)
                .accessibilityIdentifier("input")
                .onSubmit { submissions += 1 }
            HStack {
                Text("Submissions: \(submissions)").accessibilityIdentifier("submissions")
                Button("Caret after 2") { placeCaret() }.accessibilityIdentifier("caret-middle")
                Text("Caret: \(caretPosition)").accessibilityIdentifier("caret-position")
            }.font(.caption)
            Button("Dismiss keyboard") { editing = false }
                .accessibilityIdentifier("dismiss")
            Button("Increment") { count += 1 }
                .accessibilityIdentifier("increment")
            Text("Count: \(count)").accessibilityIdentifier("counter")
            HStack {
                Button("Change target soon") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { mutableTitle = "Mutable B" }
                }.accessibilityIdentifier("schedule-change")
                Button(mutableTitle) { count += 100 }.accessibilityIdentifier("mutable-target")
            }.font(.caption)
            Button("Web & dialog probes") { showExtendedProbes = true }
                .accessibilityIdentifier("open-extended")
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(0..<40) { index in
                        Text("Row \(index)")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("row-\(index)")
                    }
                }
            }.accessibilityIdentifier("scroll")
        }.padding()
            .sheet(isPresented: $showExtendedProbes) { ExtendedProbes() }
    }

    // Fixture-only control: set and report a known insertion point independently of XCTest.
    private func placeCaret() {
        func field(in view: UIView) -> UITextField? {
            if let input = view as? UITextField { return input }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow), let input = field(in: window),
              let position = input.position(from: input.beginningOfDocument, offset: 2) else { caretPosition = -1; return }
        input.becomeFirstResponder()
        input.selectedTextRange = input.textRange(from: position, to: position)
        caretPosition = input.selectedTextRange.map { input.offset(from: input.beginningOfDocument, to: $0.start) } ?? -1
    }
}
