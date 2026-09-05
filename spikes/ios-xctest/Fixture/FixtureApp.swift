import SwiftUI

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
            Button("Dismiss keyboard") { editing = false }
                .accessibilityIdentifier("dismiss")
            Button("Increment") { count += 1 }
                .accessibilityIdentifier("increment")
            Text("Count: \(count)").accessibilityIdentifier("counter")
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
}
