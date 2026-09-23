import AVFoundation
import NotchPilotCore

import Speech

/// Audio engine and conversion live on a dedicated serial queue, never the UI thread.
final class AudioCapture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "NotchPilot.audio", qos: .userInitiated)
    private var engine: AVAudioEngine?
    func start(format: AVAudioFormat, yield: @escaping @Sendable (AnalyzerInput) -> Void, level: @escaping @Sendable (Float) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let engine = AVAudioEngine()
                    let input = engine.inputNode
                    let native = input.outputFormat(forBus: 0)
                    guard native.sampleRate > 0, native.channelCount > 0, let converter = AVAudioConverter(from: native, to: format) else { throw PilotError.unavailable("No usable microphone. Check Sound settings.") }
                    var lastLevel = Date.distantPast
                    input.installTap(onBus: 0, bufferSize: 2048, format: native) { buffer, _ in
                        // The tap's buffer is borrowed. Copy before returning it to AVAudioEngine.
                        guard let copy = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: buffer.frameLength) else { return }
                        copy.frameLength = buffer.frameLength
                        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                        for (a, b) in zip(source, target) { if let from = a.mData, let to = b.mData { memcpy(to, from, Int(a.mDataByteSize)) } }
                        self.queue.async {
                            guard self.engine != nil else { return }
                            let capacity = AVAudioFrameCount(Double(copy.frameLength) * format.sampleRate / native.sampleRate) + 32
                            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
                            var supplied = false
                            var error: NSError?
                            let status = converter.convert(to: output, error: &error) { _, state in
                                if supplied { state.pointee = .noDataNow; return nil }
                                supplied = true; state.pointee = .haveData; return copy
                            }
                            if status != .error, output.frameLength > 0 { yield(AnalyzerInput(buffer: output)) }
                            if Date().timeIntervalSince(lastLevel) > 0.08, let data = copy.floatChannelData?[0] {
                                var sum: Float = 0
                                for i in 0..<Int(copy.frameLength) { sum += data[i] * data[i] }
                                level(min(1, sqrt(sum / Float(max(1, copy.frameLength))) * 12)); lastLevel = Date()
                            }
                        }
                    }
                    self.engine = engine
                    engine.prepare(); try engine.start(); continuation.resume()
                } catch { self.engine?.inputNode.removeTap(onBus: 0); self.engine = nil; continuation.resume(throwing: error) }
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.engine?.stop(); self.engine?.inputNode.removeTap(onBus: 0); self.engine = nil
                continuation.resume()
            }
        }
    }
}
