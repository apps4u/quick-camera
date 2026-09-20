/* AVFoundation predates Swift concurrency annotations; see QCAppDelegate. */
@preconcurrency import AVFoundation
import Foundation
import Speech
import os

@MainActor
protocol QCVoiceListenerDelegate: AnyObject {
    /// The trigger word was heard.
    func voiceListenerDidHearTrigger()
    /// Listening could not start or stopped working; `message` is user-facing.
    func voiceListener(failedWith message: String)
}

/// Listens to the microphone and tells its delegate when the "snap" trigger word is
/// spoken. Transcription runs fully on-device via SpeechAnalyzer, and the microphone
/// is captured with its own AVAudioEngine so the camera pipeline is untouched.
@MainActor
final class QCVoiceListener {

    weak var delegate: QCVoiceListenerDelegate?
    private(set) var isListening = false

    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var lastTriggerDate: Date?

    private let logger = Logger(
        subsystem: "com.simonguest.QCamera", category: "QCVoiceListener")

    /// Starts listening. Returns false after reporting the reason via the delegate if
    /// the microphone, permissions, or transcription assets are unavailable.
    func start() async -> Bool {
        guard !isListening else { return true }

        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            delegate?.voiceListener(
                failedWith:
                    "Quick Camera needs permission to use the microphone to hear the \"\(QCVoiceCommand.triggerWord)\" command. Grant access in System Settings > Privacy & Security > Microphone."
            )
            return false
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        else {
            delegate?.voiceListener(
                failedWith: "Unfortunately, speech transcription is not available for your language."
            )
            return false
        }

        do {
            // volatile + fast results so the command is recognised as it is spoken
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

            // one-time model download; a no-op once the assets are installed
            if let installation = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber])
            {
                try await installation.downloadAndInstall()
            }

            guard
                let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber])
            else {
                delegate?.voiceListener(
                    failedWith: "Unfortunately, voice commands could not be started.")
                return false
            }

            let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.start(inputSequence: inputSequence)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let microphoneFormat = inputNode.outputFormat(forBus: 0)
            guard microphoneFormat.sampleRate > 0 else {
                delegate?.voiceListener(
                    failedWith:
                        "Unfortunately, no microphone could be found to listen for the \"\(QCVoiceCommand.triggerWord)\" command."
                )
                await analyzer.cancelAndFinishNow()
                return false
            }

            // the tap runs on an audio thread; the converter is only ever touched there
            let converter = QCVoiceAudioConverter(outputFormat: analyzerFormat)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: microphoneFormat) {
                buffer, _ in
                guard let converted = converter.convert(buffer) else { return }
                inputBuilder.yield(AnalyzerInput(buffer: converted))
            }
            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.analyzer = analyzer
            self.inputBuilder = inputBuilder
            self.resultsTask = Task { [weak self] in
                await self?.consumeResults(from: transcriber)
            }

            isListening = true
            logger.info("Voice listener started")
            return true
        } catch {
            logger.error(
                "Could not start voice listener: \(error.localizedDescription, privacy: .public)")
            delegate?.voiceListener(
                failedWith:
                    "Unfortunately, voice commands could not be started. The speech model may still need to download; check your network connection and try again."
            )
            stop()
            return false
        }
    }

    func stop() {
        resultsTask?.cancel()
        resultsTask = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        isListening = false
        logger.info("Voice listener stopped")
    }

    private func consumeResults(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let transcript = String(result.text.characters)
                guard QCVoiceCommand.containsTrigger(transcript) else { continue }
                let now = Date.now
                guard QCVoiceCommand.shouldFire(at: now, lastFired: lastTriggerDate) else {
                    continue
                }
                lastTriggerDate = now
                logger.info("Voice trigger recognised")
                delegate?.voiceListenerDidHearTrigger()
            }
        } catch is CancellationError {
            // stopped deliberately
        } catch {
            guard !Task.isCancelled else { return }
            logger.error(
                "Voice transcription stopped: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Converts microphone buffers to the analyzer's required format. Only the audio tap
/// touches this after creation, and taps deliver buffers serially, so the mutable
/// converter state is safe despite the Sendable annotation.
private final class QCVoiceAudioConverter: @unchecked Sendable {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.format != outputFormat else { return buffer }
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(capacity, 1))
        else { return nil }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}
