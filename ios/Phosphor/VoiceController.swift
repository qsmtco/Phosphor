import Foundation
import AVFoundation
import Speech

// MARK: - VoiceController
//
// Push-to-talk voice input: tap mic -> live speech recognition -> tap again ->
// final transcript delivered via onTranscript callback.

@MainActor
final class VoiceController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle, requesting, recording, denied, unavailable
        case error(String)
    }

    @Published var state: State = .idle
    @Published var partialText: String = ""

    var onTranscript: ((String) -> Void)?

    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var isStopping = false   // re-entrancy guard

    static let shared = VoiceController()

    func toggle() {
        switch state {
        case .recording:
            stop()
        case .idle:
            start()
        default:
            break
        }
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        defer { isStopping = false }

        // Capture the transcript BEFORE tearing anything down
        let finalText = partialText.trimmingCharacters(in: .whitespacesAndNewlines)

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        partialText = ""
        state = .idle

        // Deliver AFTER state cleanup: guarantees a clean slate for the next
        // session, and the send happens with no recognition machinery in play.
        if !finalText.isEmpty {
            print("[Voice] transcript: \(finalText)")
            onTranscript?(finalText)
        }
    }

    private func start() {
        partialText = ""

        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        let micAuth = AVAudioSession.sharedInstance().recordPermission

        switch (speechAuth, micAuth) {
        case (.authorized, .granted):
            beginSession()
        case (.notDetermined, _):
            state = .requesting
            SFSpeechRecognizer.requestAuthorization { [weak self] _ in
                Task { @MainActor in
                    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] _ in
                        Task { @MainActor in
                            self?.start()
                        }
                    }
                }
            }
        default:
            state = .denied
        }
    }

    private func beginSession() {
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let rec, rec.isAvailable else {
            state = .unavailable
            return
        }
        recognizer = rec

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            state = .error("audio session: \(error.localizedDescription)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .error("engine: \(error.localizedDescription)")
            return
        }

        task = rec.recognitionTask(with: request) { [weak self] result, err in
            Task { @MainActor in
                guard let self, self.state == .recording else { return }
                if let result {
                    self.partialText = result.bestTranscription.formattedString
                }
                // NOTE: do NOT stop() from inside the callback on error;
                // err fires on every task invalidation including our own
                // stop() -> re-entrancy. The stop() path owns cleanup.
            }
        }

        state = .recording
    }
}
