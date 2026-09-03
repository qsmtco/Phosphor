import Foundation
import UIKit
import WebKit
import Combine

// MARK: - NFCBridge
//
// Bridges native NFC tag scanning to the WKWebView host.
//
// Message Name: "eagleNFC"
// Expected payload shape from JS: { "requestId": String }
//
// Contract:
// - One in-flight request at a time. A second concurrent message resolves immediately
//   with { "requestId": String, "error": "busy" } and leaves the active scan running.
// - Invalid or missing requestId: message is ignored (logged only).
// - Scanner detection: resolves { "requestId": id, "uid": uid }
// - Scanner error/cancellation: resolves { "requestId": id, "error": mappedError }
//   Cancellation detection is entirely errorMessage-driven ($errorMessage sink),
//   eliminating any race condition with fast scan detections.
// - App backgrounding: listens for UIApplication.didEnterBackgroundNotification (willResignActive
//   is deliberately NOT used because CoreNFC sheet presentation triggers it); if a request
//   is in flight, immediately cancels the scanner and resolves { "requestId": id, "error": "cancelled" }
//   so the bridge never remains permanently busy.
//
// Error Mapping Table:
// ┌────────────────────────────────────────────────────────────┬─────────────────────────────┐
// │ Raw scanner / delegate error condition                     │ Resolved error value        │
// ├────────────────────────────────────────────────────────────┼─────────────────────────────┤
// │ Second concurrent message while in-flight                  │ "busy"                      │
// │ Session invalidated by user ("Session invalidated by user")│ "cancelled"                 │
// │ Error message contains "invalidated" and no "timeout"/"failed" │ "cancelled"             │
// │ Any timeout/timed-out message                              │ "timeout"                   │
// │ Any other scanner error message                            │ Passed through verbatim     │
// └────────────────────────────────────────────────────────────┴─────────────────────────────┘
//
// Resolution format:
// Resolves results by writing a percent-encoded JSON payload to WKHTTPCookieStore
// via HTTPCookie named `phosphorNFCResult`. The web page polls `document.cookie` every 250ms,
// reads and deletes the cookie, and extracts { requestId, uid, error, events }.
// This avoids any dependency on WKUserScript injection or JS execution.

@MainActor
final class NFCBridge: NSObject, ObservableObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    let scanner: NFCScanner
    private var cancellables = Set<AnyCancellable>()

    private var inFlightRequestId: String?
    private var diagEvents: [String] = []

    // Default param must NOT construct NFCScanner() in the signature:
    // default-argument evaluation is nonisolated, and NFCScanner.init is
    // @MainActor-isolated — the compiler rejects the call there (run #19
    // NFCBridge.swift:50:59). Construct inside the @MainActor body instead.
    init(webView: WKWebView? = nil, scanner: NFCScanner? = nil) {
        self.webView = webView
        self.scanner = scanner ?? NFCScanner()
        super.init()
        bindScanner()
        bindNotifications()
    }

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func tearDown() {
        scanner.cancel()
        if let id = inFlightRequestId {
            inFlightRequestId = nil
            resolve(payload: ["requestId": id, "error": "cancelled", "events": diagEvents])
        }
    }

    private func bindScanner() {
        scanner.$detectedUid
            .compactMap { $0 }
            .sink { [weak self] uid in
                guard let self = self, let reqId = self.inFlightRequestId else { return }
                self.inFlightRequestId = nil
                self.diag("native:uid:\(uid)")
                self.resolve(payload: ["requestId": reqId, "uid": uid, "events": self.diagEvents])
            }
            .store(in: &cancellables)

        scanner.$errorMessage
            .compactMap { $0 }
            .sink { [weak self] rawMsg in
                guard let self = self, let reqId = self.inFlightRequestId else { return }
                self.inFlightRequestId = nil
                let mapped = Self.mapScannerError(rawMsg)
                self.diag("native:err:\(mapped)")
                self.resolve(payload: ["requestId": reqId, "error": mapped, "events": self.diagEvents])
            }
            .store(in: &cancellables)
    }

    private func bindNotifications() {
        // CoreNFC's system scan sheet itself fires willResignActive when it
        // appears — subscribing to it cancelled every scan at sheet-open
        // (builds 25–35, root cause of the "sheet up, sheet down, no punch"
        // field behavior). didEnterBackground fires only when the user
        // actually leaves the app, which is the event we mean.
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
    }

    private func handleAppDidEnterBackground() {
        guard let reqId = inFlightRequestId else { return }
        inFlightRequestId = nil
        scanner.cancel()
        resolve(payload: ["requestId": reqId, "error": "cancelled", "events": diagEvents])
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "phosphorNFC" else { return }
        Task { @MainActor in
            self.handleMessage(body: message.body)
        }
    }

    func handleMessage(body: Any) {
        guard let dict = body as? [String: Any],
              let requestId = dict["requestId"] as? String,
              !requestId.isEmpty else {
            return
        }

        if inFlightRequestId != nil {
            resolve(payload: ["requestId": requestId, "error": "busy", "events": diagEvents])
            return
        }

        diagEvents.removeAll()
        inFlightRequestId = requestId
        scanner.reset()
        scanner.start()
        diag("native:scan-started")
    }

    // MARK: - Error Mapping Pure Function

    /// nonisolated: pure function, no state — nonisolated XCTest
    /// methods call it from NFCBridgeContractTests.swift (run #21 fix,
    /// mirror of the NFCScanner statics fix from run #20).
    nonisolated static func mapScannerError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("invalidated") && !lower.contains("timeout") && !lower.contains("failed") {
            return "cancelled"
        }
        // CoreNFC timeout messages arrive as prose ("Scan cancelled or timed
        // out. Tap to try again.") — normalize to the short code so the page
        // renders "Scan failed: timeout." not a double-"Scan" sentence.
        if lower.contains("timed out") || lower.contains("timeout") {
            return "timeout"
        }
        return message
    }

    // MARK: - Pure JS Call Builder (Legacy)

    /// nonisolated: pure function, no state — nonisolated XCTest
    /// methods call it from NFCBridgeContractTests.swift (run #21 fix,
    /// mirror of the NFCScanner statics fix from run #20).
    // Legacy eval-based builder — kept for contract tests; unused at runtime (cookie channel is live).
    nonisolated static func resolveJS(payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return "window.__phosphorNFCResolve(\(jsonString))"
    }

    // MARK: - Pure Result Payload JSON Builder

    /// nonisolated: pure, no state — test-callable.
    /// Returns the raw JSON string (NOT percent-encoded) for the result payload.
    nonisolated static func resultPayloadJSON(payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    private func resolve(payload: [String: Any]) {
        #if DEBUG
        lastResolvedJSForTest = Self.resolveJS(payload: payload)
        #endif
        guard let json = Self.resultPayloadJSON(payload: payload) else {
            print("[NFCBridge] resultPayloadJSON FAILED — payload not serializable")
            return
        }
        // Phosphor loads the shell via loadFileURL (null origin) — HTTP cookies
        // are unreliable there. Resolve directly through the page-world
        // userscript function (buffered handshake guarantees no lost payloads).
        webView?.evaluateJavaScript(
            "window.__phosphorNFCResolve?.(\(json))"
        ) { _, error in
            if let error = error {
                print("[NFCBridge] resolve eval failed: \(error.localizedDescription)")
            }
        }
    }

    private func diag(_ msg: String) {
        diagEvents.append(msg)
    }

    // MARK: - Test Seams

    #if DEBUG
    var lastResolvedJSForTest: String?
    var inFlightRequestIdForTest: String? { inFlightRequestId }
    func setInFlightRequestIdForTest(_ id: String?) {
        inFlightRequestId = id
    }
    #endif
}
