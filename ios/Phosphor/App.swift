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

// MARK: - App Entry Point

@main
// MARK: - Approval request (PHOS-SPEC-001 §8, native SwiftUI card)

struct ApprovalRequest: Identifiable {
    let id: String        // approval_id from the server
    let command: String
}

struct PhosphorApp: App {
    @StateObject private var connectivity = ConnectivityMonitor()
    @StateObject private var voice = VoiceController.shared
    @State private var reloadToken = 0
    @State private var configured = ServerConfig.isConfigured
    @State private var approval: ApprovalRequest?

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
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("phosphorApprovalRequest"))) { note in
                if let id = note.userInfo?["approval_id"] as? String,
                   let cmd = note.userInfo?["command"] as? String {
                    approval = ApprovalRequest(id: id, command: cmd)
                }
            }
            .alert("Destructive command", isPresented: Binding(
                get: { approval != nil },
                set: { if !$0 { approval = nil } }
            )) {
                Button("Approve", role: .destructive) {
                    if let a = approval { handleApproval(a, approved: true) }
                    approval = nil
                }
                Button("Deny", role: .cancel) {
                    if let a = approval { handleApproval(a, approved: false) }
                    approval = nil
                }
            } message: {
                Text(approval?.command ?? "")
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
            .onReceive(voice.$partialText) { partial in
                guard let js = Self.jsCall("window.phosphor?.voicePreview", [partial]) else { return }
                NotificationCenter.default.post(
                    name: Notification.Name("phosphorEvalJSForShell"),
                    object: nil, userInfo: ["js": js])
            }
            .onReceive(voice.$state) { st in
                // Push recording state into the page so the mic button turns
                // red while recording (and back to green on stop).
                let flag = (st == .recording) ? "true" : "false"
                if let js = Self.jsCall("window.phosphor?.voiceState", [flag]) {
                    NotificationCenter.default.post(
                        name: Notification.Name("phosphorEvalJSForShell"),
                        object: nil, userInfo: ["js": js])
                }
                if case .error(let m) = st {
                    if let js = Self.jsCall("window.phosphor?.voiceError", [m]) {
                        NotificationCenter.default.post(
                            name: Notification.Name("phosphorEvalJSForShell"),
                            object: nil, userInfo: ["js": js])
                    }
                }
            }
            .onAppear {
                // Deliver final transcripts into the page
                VoiceController.shared.onTranscript = { text in
                    if let js = Self.jsCall("window.phosphor?.sendFromVoice", [text]) {
                        NotificationCenter.default.post(
                            name: Notification.Name("phosphorEvalJSForShell"),
                            object: nil, userInfo: ["js": js])
                    }
                }
            }
        }
    }

        nonisolated static func jsCall(_ tmpl: String, _ args: [String]) -> String? {
        // Single-arg calls pass the value directly (sendFromVoice("hi")),
        // NOT as a JSON array - the page functions expect plain strings.
        if args.count == 1 {
            guard let data = try? JSONSerialization.data(withJSONObject: [args[0]]),
                  let list = String(data: data, encoding: .utf8) else { return nil }
            return "\(tmpl)(\(list.dropFirst().dropLast())); void 0"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let list = String(data: data, encoding: .utf8) else { return nil }
        return "\(tmpl)(\(list)); void 0"
    }

    private func handleApproval(_ a: ApprovalRequest, approved: Bool) {
        let server = ServerConfig.server
        guard let url = URL(string: server + "/approve") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 130
        let body: [String: Any] = ["key": ServerConfig.token,
                                   "approval_id": a.id,
                                   "deny": !approved,
                                   "session": "ios-approval"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            var js: String
            if let d = data,
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               obj["ok"] as? Bool == true {
                if approved {
                    let exit = obj["exit"] as? Int ?? -1
                    let out = (obj["output"] as? String ?? "")
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "`", with: "\\`")
                        .replacingOccurrences(of: "$", with: "\\$")
                    js = "window.phosphor?.approvalResult?.(true, 'exit \(exit)', `\(out)`); void 0"
                } else {
                    js = "window.phosphor?.approvalResult?.(false, 'denied', ''); void 0"
                }
            } else {
                js = "window.phosphor?.approvalResult?.(false, 'approval failed', ''); void 0"
            }
            NotificationCenter.default.post(
                name: Notification.Name("phosphorEvalJSForShell"),
                object: nil, userInfo: ["js": js])
        }.resume()
    }
}
