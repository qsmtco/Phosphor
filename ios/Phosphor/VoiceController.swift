import Foundation
import AVFoundation
import Speech

// MARK: - VoiceController
//
// Push-to-talk voice input: tap mic -> live speech recognition -> tap again ->
// final transcript delivered via onTranscript callback.
//
// Uses SFSpeechRecognizer (Apple speech, on-device when available, Apple server
// otherwise) — no API keys, no cost. Live partial results are exposed via
// @Published partialText so the UI can show text forming.

@MainActor
final class VoiceController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle          // not recording
        case requesting    // asking permission
        case recording     // live, listening
        case denied        // user refused mic/speech permission
        case unavailable   // device/service can't do speech
        case error(String) // fatal message
    }

    @Published var state: State = .idle
    @Published var partialText: String = ""

    /// Called once with the final transcript when the user stops recording.
    var onTranscript: ((String) -> Void)?

    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    override private init() {
        super.init()
    }

    static let shared = VoiceController()

    // MARK: public API

    /// Tap-to-toggle. Starts or stops a recognition session.
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
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        // Deactivate the session so the speaker/route returns to normal
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if let p = partialText.trimmingCharacters(in: .whitespacesAndNewlines) as String?, !p.isEmpty {
            onTranscript?(p)
        }
        partialText = ""
        state = .idle
    }

    // MARK: internals

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
                            self?.start() // re-evaluate with new permissions
                        }
                    }
                }
            }
        default:
            state = .denied
        }
    }

    private func beginSession() {
        // Locale: en-US (Captain's locale). On-device when the device supports it.
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let rec, rec.isAvailable else {
            state = .unavailable
            return
        }
        recognizer = rec

        // Audio session: measurement-friendly, record
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
        if rec.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = false // prefer server accuracy; fallback auto
        }
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
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partialText = text
                    if result.isFinal {
                        // finalize on next runloop tick via stop()
                    }
                }
                if err != nil {
                    // Session ended (user stop, silence timeout). Treat like stop.
                    if self.state == .recording { self.stop() }
                }
            }
        }

        state = .recording
    }
}
