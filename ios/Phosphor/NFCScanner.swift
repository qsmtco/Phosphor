import SwiftUI
import CoreNFC

// MARK: - NFCScanner (ObservableObject)
//
// Wraps NFCTagReaderSession. The session runs on a background queue; we
// hop to MainActor before updating @Published properties. Each session
// is single-use — the system invalidates it after a tag is read or the
// user cancels. Callers create a new NFCScanner per scan attempt, OR
// call `reset()` between attempts on a shared instance (the retry path
// after a timeout).

@MainActor
final class NFCScanner: NSObject, ObservableObject {
    @Published var detectedUid: String? = nil
    @Published var errorMessage: String? = nil
    /// True if the most recent attempt ended in a retryable error (timeout,
    /// user cancel, connect failure). Used by the view to keep the start
    /// button tappable after a non-fatal error.
    @Published private(set) var hasError: Bool = false

    private var session: NFCTagReaderSession?
    private var hasFired = false

    #if DEBUG
    var hasFiredForTest: Bool { hasFired }
    var hasErrorForTest: Bool { hasError }
    var isCancelledForTest: Bool = false
    #endif

    /// True if the device hardware supports NFC tag reading at all.
    nonisolated static var isHardwareAvailable: Bool {
        NFCTagReaderSession.readingAvailable
    }

    /// Normalizes raw byte identifiers to uppercase hex without delimiters.
    /// Accepts 4, 7, and 10 byte UIDs — mirroring the shared contract
    /// (packages/shared timeclock.ts VALID_HEX_LENGTHS 8/14/20 hex = 4/7/10 bytes).
    /// nonisolated: pure function, no state — the nonisolated NFCTagReaderSession
    /// delegate (background queue) calls it directly.
    nonisolated static func normalizeUid(_ data: Data) -> String? {
        guard data.count == 4 || data.count == 7 || data.count == 10 else { return nil }
        return data.map { String(format: "%02X", $0) }.joined()
    }

    func start() {
        if hasFired {
            hasFired = false
            hasError = false
            errorMessage = nil
            detectedUid = nil
            session = nil
        }

        #if DEBUG
        isCancelledForTest = false
        #endif

        guard !hasFired else { return }
        guard NFCTagReaderSession.readingAvailable else {
            errorMessage = "This device does not support NFC tag scanning."
            hasError = true
            return
        }
        let session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil)
        session?.alertMessage = "Hold your iPhone near the Phosphor tag."
        self.session = session
        self.hasError = false
        session?.begin()
    }

    func reset() {
        hasFired = false
        hasError = false
        errorMessage = nil
        detectedUid = nil
        session = nil
        #if DEBUG
        isCancelledForTest = false
        #endif
    }

    func cancel() {
        #if DEBUG
        isCancelledForTest = true
        #endif
        session?.invalidate()
        session = nil
    }

    func fireScanned(_ uid: String) {
        guard !hasFired else { return }
        hasFired = true
        detectedUid = uid
        hasError = false
        session?.invalidate()
        session = nil
    }

    func fireError(_ message: String) {
        guard !hasFired else { return }
        hasFired = true
        errorMessage = message
        hasError = true
        session?.invalidate()
        session = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCScanner: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // No state to update; the session is now polling.
    }

    nonisolated func tagReaderSession(
        _ session: NFCTagReaderSession,
        didDetect tags: [NFCTag]
    ) {
        guard let firstTag = tags.first else {
            Task { @MainActor in
                self.fireError("No tag found. Try again.")
            }
            return
        }
        session.connect(to: firstTag) { error in
            if let error = error {
                Task { @MainActor in
                    if self.hasFired && self.detectedUid != nil { return }
                    self.fireError("Could not read tag: \(error.localizedDescription). Try again.")
                }
                return
            }
            guard case .miFare(let miFareTag) = firstTag else {
                Task { @MainActor in
                    if self.hasFired && self.detectedUid != nil { return }
                    self.fireError("Unsupported tag type.")
                }
                return
            }
            let identifier = miFareTag.identifier
            let normalized = NFCScanner.normalizeUid(identifier)
            Task { @MainActor in
                if let uid = normalized {
                    self.fireScanned(uid)
                } else {
                    self.fireError("Tag read but UID was the wrong length.")
                }
            }
        }
    }

    nonisolated func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        let isUserCanceled = (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled
        Task { @MainActor in
            if self.hasFired { return }
            if isUserCanceled {
                self.fireError("Session invalidated by user")
            } else {
                self.fireError("Scan cancelled or timed out. Tap to try again.")
            }
        }
    }
}
