import SwiftUI
import Network

// MARK: - ConnectivityMonitor
// (Adapted from Eagle Timeclock's proven pattern - qsmtco internal reuse.)

@MainActor
final class ConnectivityMonitor: ObservableObject {
    @Published var isOnline: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.qsmtco.phosphor.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// MARK: - Native Setup Screen (shown when no config saved)

struct SetupView: View {
    let onSaved: () -> Void
    @State private var server: String = ""
    @State private var token: String = ""
    @State private var error: String = ""

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.13).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "circle.circle")
                    .font(.system(size: 64))
                    .foregroundColor(Color(red: 0.95, green: 0.96, blue: 0.97))
                    .padding(.bottom, 8)
                Text("Phosphor")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Color(red: 0.87, green: 0.89, blue: 0.93))
                    .padding(.bottom, 40)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Connect to DragonCakes")
                        .font(.headline)
                        .foregroundColor(.white)
                    TextField("https://phosphor.smtco.co", text: $server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                    SecureField("access token (dcui_…)", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                    if !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Color(red: 1, green: 0.55, blue: 0.65))
                    }
                    Button(action: save) {
                        Text("Save & connect")
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color(red: 0.49, green: 1.0, blue: 0.70))
                            .foregroundColor(Color(red: 0.06, green: 0.14, blue: 0.10))
                            .fontWeight(.semibold)
                            .cornerRadius(10)
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.06))
                .cornerRadius(16)
                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private func save() {
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("http"), !t.isEmpty else {
            error = "Server must start with http(s):// and token is required."
            return
        }
        ServerConfig.save(server: s, token: t)
        onSaved()
    }
}

// MARK: - Mic Button (push-to-talk overlay)

struct MicButton: View {
    @StateObject private var voice = VoiceController.shared
    let onTranscript: (String) -> Void

    var body: some View {
        Button(action: { voice.toggle() }) {
            ZStack {
                Circle()
                    .fill(voice.state == .recording
                          ? Color(red: 1.0, green: 0.37, blue: 0.49)
                          : Color(red: 0.29, green: 0.85, blue: 0.47))
                    .frame(width: 56, height: 56)
                    .shadow(color: (voice.state == .recording
                        ? Color(red: 1.0, green: 0.37, blue: 0.49)
                        : Color(red: 0.29, green: 0.85, blue: 0.47)).opacity(0.5),
                        radius: voice.state == .recording ? 14 : 7)
                Image(systemName: voice.state == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color(red: 0.06, green: 0.14, blue: 0.10))
            }
        }
        .onChange(of: voice.partialText) { _ in
            // live partial preview is shown by the page via setVoicePreview
            let p = voice.partialText
            webViewEval("window.phosphor?.voicePreview?.(\(jsonString(p)))")
        }
        .onChange(of: voice.state) { newState in
            if newState == .idle {
                // stop() already delivered transcript via onTranscript
            } else if case .error(let msg) = newState {
                webViewEval("window.phosphor?.voiceError?.(\(jsonString(msg)))")
            } else if newState == .denied {
                webViewEval("window.phosphor?.voiceError?.('Microphone/Speech permission denied - enable in Settings')")
            } else if newState == .unavailable {
                webViewEval("window.phosphor?.voiceError?.('Speech recognition unavailable')")
            }
        }
    }

    private func jsonString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        return String(data: data ?? Data("[]".utf8), encoding: .utf8).map { String($0.dropFirst().dropLast()) } ?? "''"
    }

    private func webViewEval(_ js: String) {
        // Routed through the shared webView reference
        NotificationCenter.default.post(
            name: Notification.Name("phosphorEvalJS"),
            object: nil,
            userInfo: ["js": js])
    }
}

// MARK: - App Entry Point

@main
struct PhosphorApp: App {
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var voice = VoiceController.shared
    @State private var reloadToken = 0
    @State private var configured = ServerConfig.isConfigured

    var body: some Scene {
        WindowGroup {
            ZStack {
                if configured {
                    ShellView(reloadToken: reloadToken)
                        .id(reloadToken)
                        .ignoresSafeArea()
                } else {
                    SetupView {
                        // Config saved natively; remount the shell so its
                        // userscript injects the fresh values.
                        configured = true
                        reloadToken += 1
                    }
                    .ignoresSafeArea()
                }
                if configured && !connectivity.isOnline {
                    OfflineView(onRetry: { reloadToken += 1 })
                }
                if configured {
                    MicButton { text in
                        // Final transcript -> shell sends it as a message
                        let js = "window.phosphor?.sendFromVoice?.(\(jsonEncode(text))); void 0"
                        NotificationCenter.default.post(
                            name: Notification.Name("phosphorEvalJS"),
                            object: nil,
                            userInfo: ["js": js])
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.init(top: 0, leading: 0, bottom: 96, trailing: 18))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("phosphorEvalJS"))) { note in
                if let js = note.userInfo?["js"] as? String {
                    // The ShellView coordinator listens and evals in its webView
                    NotificationCenter.default.post(
                        name: Notification.Name("phosphorEvalJSForShell"),
                        object: nil,
                        userInfo: ["js": js])
                }
            }
        }
    }

    private func jsonEncode(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        return String(data: data ?? Data("''".utf8), encoding: .utf8).map { String($0.dropFirst().dropLast()) } ?? "''"
    }
}
