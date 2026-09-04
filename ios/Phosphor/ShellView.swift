import SwiftUI
import WebKit

// MARK: - ShellView
//
// Fullscreen container embedding WKWebView that loads the BUNDLED app-shell.html
// (generative-UI client for the DragonCakes agent server).
//
// Adapted from Eagle Timeclock's ShellView (proven NFC handshake pattern kept):
// - Injects __phosphorNFCRegister/__phosphorNFCResolve buffered userscript at
//   document start (renamed from eagleNFC).
// - NFC results resolve via HTTPCookie "phosphorNFCResult" (domain set to
//   "localhost" so it works with the bundled-file page).
// - Navigation policy: local files + the configured agent server host only.
//
// Server config (address + token) is injected from UserDefaults into the page
// via a second userscript BEFORE app-shell.html runs, so the page boots
// straight into CONNECTING without a setup screen (setup remains available
// in-page if the config is wrong).

enum ServerConfig {
    static var server: String {
        UserDefaults.standard.string(forKey: "ph.server") ?? ""
    }
    static var token: String {
        UserDefaults.standard.string(forKey: "ph.token") ?? ""
    }
    static var isConfigured: Bool {
        !server.isEmpty && !token.isEmpty
    }
    static func save(server: String, token: String) {
        UserDefaults.standard.set(server, forKey: "ph.server")
        UserDefaults.standard.set(token, forKey: "ph.token")
    }
}

struct ShellView: UIViewRepresentable {
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        // ── NFC handshake userscript (document start, page world) ──
        let nfcJS = """
        window.__phosphorNFCDiagLog = ["page:userscript-ran"];
        window.__phosphorNFCDiag = window.__phosphorNFCDiag || ((m) => {
          (window.__phosphorNFCDiagLog ||= []).push(String(m));
        });
        window.__phosphorNFCRegister = (id, fn) => {
          (window.__phosphorNFCPending ||= new Map()).set(id, fn);
          const buf = (window.__phosphorNFCBuffer ||= []);
          for (let i = 0; i < buf.length; ) {
            if (buf[i].requestId === id) {
              const p = buf.splice(i, 1)[0];
              fn(p);
            } else {
              i++;
            }
          }
        };
        window.__phosphorNFCResolve = (payload) => {
          const p = (window.__phosphorNFCPending ||= new Map());
          const h = p.get(payload.requestId);
          if (h) {
            p.delete(payload.requestId);
            h(payload);
          } else {
            (window.__phosphorNFCBuffer ||= []).push(payload);
          }
        };
        // Convenience API for generated screens (agent HTML can call these):
        window.phosphor = window.phosphor || {};
        window.phosphor.nfcScan = (id) => {
          window.webkit?.messageHandlers?.phosphorNFC?.postMessage({ requestId: id });
        };
        """
        let nfcScript = WKUserScript(
            source: nfcJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        configuration.userContentController.addUserScript(nfcScript)

        // ── Server config injection (document start, page world) ──
        let server = ServerConfig.server
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\n", with: "")
        // R-SEC-2 (PHOS-SPEC-001): the token must NOT be page-visible.
        // It is held natively and attached by the phosphorApi proxy handler.
        let token = ServerConfig.token
        let configJS = """
        window.PH_SERVER = "\(server)";
        try { localStorage.setItem("ph:server", window.PH_SERVER); } catch (e) {}
        // M7 (P3 audit): purge pre-spec tokens from page storage entirely
        try { localStorage.removeItem("ph:token"); } catch (e) {}
        """
        let configScript = WKUserScript(
            source: configJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        configuration.userContentController.addUserScript(configScript)

        let bridge = context.coordinator.bridge
        configuration.userContentController.add(bridge, name: "phosphorNFC")
        configuration.userContentController.add(context.coordinator, name: "phosphorConfig")
        configuration.userContentController.add(context.coordinator, name: "phosphorMic")
        configuration.userContentController.add(context.coordinator, name: "phosphorApi")
        configuration.userContentController.add(context.coordinator, name: "phosphorApproval")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        bridge.attach(webView: webView)
        context.coordinator.webView = webView

        // Load the BUNDLED shell (no network needed for the UI itself).
        // xcodegen "type: folder" may nest it under ios-app/ - try candidates
        // and log every miss so a packaging change is visible in Console.
        if let shellURL = Self.locateShell() {
            print("[Phosphor] shell found at:", shellURL.path)
            webView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())
        } else {
            print("[Phosphor] FATAL: app-shell.html not found in bundle. Bundle contents:")
            if let resourcePath = Bundle.main.resourcePath,
               let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                for item in contents { print("  -", item) }
            }
            let errHtml = """
                <html><body style="background:#1c1d22;color:#ff5e7c;font-family:monospace;
                display:grid;place-items:center;height:100vh;margin:0">
                <div style="text-align:center">PACKAGING ERROR<br>app-shell.html missing</div>
                </body></html>
                """
            webView.loadHTMLString(errHtml, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.bridge.tearDown()
            if let shellURL = ShellView.locateShell() {
                uiView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())
            }
        }
    }

    /// Find app-shell.html wherever the packaging put it.
    nonisolated static func locateShell() -> URL? {
        let bundle = Bundle.main
        // 1. At bundle root (plain resource copy)
        if let u = bundle.url(forResource: "app-shell", withExtension: "html") {
            return u
        }
        // 2. Inside a copied folder reference (ios-app/)
        if let u = bundle.url(forResource: "app-shell", withExtension: "html",
                              subdirectory: "ios-app") {
            return u
        }
        // 3. Brute-force scan the bundle for it (folder refs can nest deeper)
        if let resourcePath = bundle.resourcePath,
           let files = FileManager.default.enumerator(atPath: resourcePath) {
            for case let f as String in files where f.hasSuffix("app-shell.html") {
                return URL(fileURLWithPath: resourcePath).appendingPathComponent(f)
            }
        }
        return nil
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.bridge.tearDown()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "phosphorNFC")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "phosphorConfig")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "phosphorMic")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "phosphorApi")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "phosphorApproval")
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let bridge = NFCBridge()
        weak var webView: WKWebView?
        var lastReloadToken: Int = 0

        // MARK: config save from the page (setup screen)
        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "phosphorMic" {
                Task { @MainActor in
                    VoiceController.shared.toggle()
                }
                return
            }
            if message.name == "phosphorApproval" {
                // PHOS-SPEC-001 §8: page asks native to show the SwiftUI
                // approval card (Captain decision 2026-09-03: native card).
                Task { @MainActor in
                    guard let dict = message.body as? [String: Any],
                          let aid = dict["approval_id"] as? String
                    else {
                        // L2 (P5 audit): malformed request must not vanish
                        webView?.evaluateJavaScript("window.phosphor?.approvalResult?.(false, 'malformed approval request', ''); void 0")
                        return
                    }
                    let cmd = (dict["command"] as? String) ?? "(server preview)"
                    NotificationCenter.default.post(
                        name: Notification.Name("phosphorApprovalRequest"),
                        object: nil,
                        userInfo: ["approval_id": aid, "command": cmd])
                }
                return
            }
            if message.name == "phosphorApi" {
                // R-SEC-2: token-attached server proxy. Page posts
                // {message, session}; we attach key natively and return the
                // JSON via window.__phApiResolve.
                Task { @MainActor in
                    guard let bodyStr = message.body as? String,
                          let data = bodyStr.data(using: .utf8),
                          var req = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else {
                        webView?.evaluateJavaScript("window.__phApiResolve && window.__phApiResolve('', {ok:false,__error:'bad request body'})")
                        return
                    }
                    req["key"] = ServerConfig.token
                    let reqId = (req["req"] as? String) ?? ""
                    let server = ServerConfig.server
                    // M6 (audit): /reset shares this token-attached proxy
                    let path = (req["__reset"] as? Bool == true) ? "/reset" : "/message"
                    guard let url = URL(string: server + path),
                          let payload = try? JSONSerialization.data(withJSONObject: req)
                    else {
                        webView?.evaluateJavaScript("window.__phApiResolve && window.__phApiResolve('\(reqId)', {ok:false,__error:'bad server url'})")
                        return
                    }
                    var urlReq = URLRequest(url: url)
                    urlReq.httpMethod = "POST"
                    urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlReq.httpBody = payload
                    urlReq.timeoutInterval = 120
                    let webViewRef = webView
                    URLSession.shared.dataTask(with: urlReq) { data, resp, err in
                        // M4 (audit): validate + re-serialize the server body.
                        // Never interpolate raw text (a tunnel 502 HTML page
                        // would break the JS and hang the promise).
                        var outDict: [String: Any] = ["ok": false,
                            "__error": err?.localizedDescription ?? "invalid server response"]
                        if let d = data,
                           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                            outDict = obj
                        }
                        outDict["req"] = reqId  // M5: route to the right request
                        guard let out = try? JSONSerialization.data(withJSONObject: outDict),
                              let outStr = String(data: out, encoding: .utf8) else { return }
                        let js = "window.__phApiResolve && window.__phApiResolve('\(reqId)', \(outStr)); void 0"
                        Task { @MainActor in
                            webViewRef?.evaluateJavaScript(js)
                        }
                    }.resume()
                }
                return
            }
            guard message.name == "phosphorConfig" else { return }
            Task { @MainActor in
                guard let dict = message.body as? [String: Any] else { return }
                let server = (dict["server"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let token = (dict["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !server.isEmpty, !token.isEmpty else { return }
                UserDefaults.standard.set(server, forKey: "ph.server")
                UserDefaults.standard.set(token, forKey: "ph.token")
                print("[Phosphor] config saved: server=\(server)")
                // Reload so the userscript re-injects the new values
                if let shellURL = ShellView.locateShell() {
                    webView?.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())
                }
            }
        }

        private var foregroundObserver: NSObjectProtocol?
        private var evalObserver: NSObjectProtocol?

        override init() {
            super.init()
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.webView?.evaluateJavaScript(
                    "window.dispatchEvent(new Event('phosphorForeground'))"
                ) { _, error in
                    if let error = error {
                        print("[ShellView] foreground event eval: \(error.localizedDescription)")
                    }
                }
            }
            // Voice/mic pipeline: evaluate JS in the page (mic transcript etc.)
            evalObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("phosphorEvalJSForShell"),
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let js = note.userInfo?["js"] as? String else { return }
                self?.webView?.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        print("[ShellView] eval failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        deinit {
            if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
            if let observer = evalObserver { NotificationCenter.default.removeObserver(observer) }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // System scheme handoff: WKWebView cannot render these — hand to
            // the OS (Phone, Messages, Mail, FaceTime). Cancel the in-webview
            // navigation and open externally.
            if let scheme = url.scheme?.lowercased(),
               ["tel", "sms", "mailto", "facetime", "facetime-audio"].contains(scheme) {
                decisionHandler(.cancel)
                UIApplication.shared.open(url, options: [:]) { opened in
                    if !opened {
                        print("[ShellView] no handler for scheme \(scheme)")
                    }
                }
                return
            }
            // Local/bundled content
            if url.scheme == "about" || url.scheme == "blob" || url.isFileURL {
                decisionHandler(.allow)
                return
            }
            // The configured agent server (so the page can fetch/render remote
            // images later) — compare host+scheme against stored config.
            if let host = url.host?.lowercased(),
               let serverHost = URL(string: ServerConfig.server)?.host?.lowercased(),
               host == serverHost {
                decisionHandler(.allow)
                return
            }
            // Google fonts + images are used by generated screens
            if url.host?.lowercased() == "fonts.googleapis.com" ||
               url.host?.lowercased() == "fonts.gstatic.com" {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }
    }
}
