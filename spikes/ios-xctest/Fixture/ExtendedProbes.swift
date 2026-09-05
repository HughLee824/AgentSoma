import SwiftUI
import UserNotifications
import WebKit

struct ExtendedProbes: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showDialog = false
    @State private var dialogResult = "Not confirmed"
    @State private var notificationStatus = "loading"

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Extended probes").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.accessibilityIdentifier("close-extended")
            }
            Button("Show dialog") { showDialog = true }.accessibilityIdentifier("show-dialog")
            Text(dialogResult).accessibilityIdentifier("dialog-result")
            Button("Request notification permission") {
                Task {
                    do {
                        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                        await refreshNotificationStatus()
                    } catch {
                        notificationStatus = "error: \(error.localizedDescription)"
                    }
                }
            }.accessibilityIdentifier("request-notifications")
            Text("Notifications: \(notificationStatus)").accessibilityIdentifier("notification-status")
            LocalWebProbe()
        }
        .padding()
        .task { await refreshNotificationStatus() }
        .alert("AgentSoma confirmation", isPresented: $showDialog) {
            Button("Confirm") { dialogResult = "Confirmed" }.accessibilityIdentifier("confirm-dialog")
            Button("Cancel", role: .cancel) {}.accessibilityIdentifier("cancel-dialog")
        } message: {
            Text("This changes only the local test label.")
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: notificationStatus = "notDetermined"
        case .denied: notificationStatus = "denied"
        case .authorized: notificationStatus = "authorized"
        case .provisional: notificationStatus = "provisional"
        case .ephemeral: notificationStatus = "ephemeral"
        @unknown default: notificationStatus = "unknown"
        }
    }
}

private struct LocalWebProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.accessibilityIdentifier = "probe-webview"
        view.loadHTMLString("""
        <!doctype html><html lang="en"><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        :root { color-scheme: light dark; font: 18px -apple-system, sans-serif; }
        body { margin: 16px; } input,button { font: inherit; padding: 12px; }
        input { box-sizing: border-box; width: 100%; margin: 8px 0 16px; }
        </style></head><body>
        <h2>Local web probe</h2>
        <label for="web-input">Web input</label>
        <input id="web-input" aria-label="Web input" placeholder="Web text"
          autocorrect="off" autocapitalize="off" autocomplete="off" spellcheck="false"
          oninput="document.getElementById('web-value').textContent='Web value: '+this.value">
        <button id="web-increment" aria-label="Web increment"
          onclick="document.getElementById('web-count').textContent='Web count: '+(++window.count)">Web increment</button>
        <p id="web-count" role="status">Web count: 0</p>
        <p id="web-value">Web value: </p>
        <script>window.count=0;</script>
        </body></html>
        """, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
