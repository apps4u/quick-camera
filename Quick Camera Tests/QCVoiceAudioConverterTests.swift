import AVFoundation
import Testing

@testable import Quick_Camera

@Suite("Voice audio conversion")
struct QCVoiceAudioConverterTests {

    /// Deinterleaved Float32, the same shape as AVAudioEngine microphone taps deliver.
    private func makeFormat(sampleRate: Double, channels: AVAudioChannelCount) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    }

    /// A buffer filled with a 440 Hz sine wave so converted output has recognisable content.
    private func makeToneBuffer(format: AVAudioFormat, frames: AVAudioFrameCount)
        -> AVAudioPCMBuffer
    {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                samples[frame] = sinf(2 * .pi * 440 * Float(frame) / Float(format.sampleRate))
            }
        }
        return buffer
    }

    @Test("A buffer already in the analyzer format passes through unchanged")
    func sameFormatPassesThrough() {
        let format = makeFormat(sampleRate: 16000, channels: 1)
        let converter = QCVoiceAudioConverter(outputFormat: format)
        let buffer = makeToneBuffer(format: format, frames: 1024)

        #expect(converter.convert(buffer) === buffer)
    }

    @Test("Microphone audio is converted to the analyzer's format")
    func convertsToAnalyzerFormat() {
        let micFormat = makeFormat(sampleRate: 48000, channels: 2)
        let analyzerFormat = makeFormat(sampleRate: 16000, channels: 1)
        let converter = QCVoiceAudioConverter(outputFormat: analyzerFormat)

        let converted = converter.convert(makeToneBuffer(format: micFormat, frames: 4800))

        #expect(converted?.format == analyzerFormat)
    }

    @Test("Downsampling preserves the audio's duration across a stream")
    func downsamplingPreservesDuration() throws {
        let micFormat = makeFormat(sampleRate: 48000, channels: 1)
        let analyzerFormat = makeFormat(sampleRate: 16000, channels: 1)
        let converter = QCVoiceAudioConverter(outputFormat: analyzerFormat)

        // The resampler withholds a little priming latency from the first buffer and
        // repays it across later ones, so duration is only meaningful over a stream:
        // one second of input should come out as roughly one second of output.
        var outputFrames = 0
        for _ in 0..<10 {
            let converted = try #require(
                converter.convert(makeToneBuffer(format: micFormat, frames: 4800)))
            outputFrames += Int(converted.frameLength)
        }
        let expectedFrames = 16000
        #expect(abs(outputFrames - expectedFrames) <= 480)  // within 30ms
    }

    @Test("Converted audio carries signal, not silence")
    func convertedAudioHasSignal() throws {
        let micFormat = makeFormat(sampleRate: 48000, channels: 1)
        let analyzerFormat = makeFormat(sampleRate: 16000, channels: 1)
        let converter = QCVoiceAudioConverter(outputFormat: analyzerFormat)

        let converted = try #require(converter.convert(makeToneBuffer(format: micFormat, frames: 4800)))
        let samples = try #require(converted.floatChannelData?[0])
        let peak = (0..<Int(converted.frameLength)).map { abs(samples[$0]) }.max() ?? 0
        #expect(peak > 0.5)
    }

    @Test("The converter handles a stream of buffers, as the audio tap delivers them")
    func convertsSequentialBuffers() throws {
        let micFormat = makeFormat(sampleRate: 48000, channels: 2)
        let analyzerFormat = makeFormat(sampleRate: 16000, channels: 1)
        let converter = QCVoiceAudioConverter(outputFormat: analyzerFormat)

        // taps deliver ~4096-frame buffers back to back; every one must convert
        for _ in 0..<5 {
            let converted = try #require(converter.convert(makeToneBuffer(format: micFormat, frames: 4096)))
            #expect(converted.format == analyzerFormat)
            #expect(converted.frameLength > 0)
        }
    }

    @Test("An empty buffer converts without producing frames or failing")
    func emptyBufferProducesNoFrames() throws {
        let micFormat = makeFormat(sampleRate: 48000, channels: 1)
        let analyzerFormat = makeFormat(sampleRate: 16000, channels: 1)
        let converter = QCVoiceAudioConverter(outputFormat: analyzerFormat)

        let empty = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: 1024)!
        let converted = try #require(converter.convert(empty))
        #expect(converted.frameLength == 0)
    }
}
