import AVFoundation
import MomentumCore
import OSLog

/// Generates background noise for focus sessions, with no audio files: white, pink (Paul Kellet's
/// filter) and brown (a leaky integrator, which sounds like steady rain).
///
/// The render block runs on the real-time audio thread, so it reads only preallocated state and
/// never allocates or locks. Volume changes ramp per sample to avoid clicks, which also gives
/// fades in and out.
@MainActor
final class FocusSoundPlayer {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let state = NoiseState()
    private var stopTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "dev.momentum.app", category: "FocusSound")

    private(set) var isPlaying = false

    /// Plays `sound` at `volume` (0 to 1), or fades out for `.off`.
    func play(_ sound: FocusSound, volume: Double) {
        guard sound != .off, volume > 0 else {
            stop()
            return
        }
        stopTask?.cancel()
        state.kind.store(Self.code(for: sound))
        state.targetGain.store(Float(volume) * 0.35)
        // The system can stop the engine under us (a call, Siri, another app's audio); then
        // this starts it again rather than believing it still plays.
        guard !isPlaying || !engine.isRunning else { return }
        do {
            try start()
            isPlaying = true
        } catch {
            logger.error("Could not start focus sound: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fades out, then stops the engine to free the audio hardware.
    func stop() {
        guard isPlaying else { return }
        state.targetGain.store(0)
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            self.engine.stop()
            self.isPlaying = false
        }
    }

    private func start() throws {
        if source == nil {
            let format = engine.outputNode.inputFormat(forBus: 0)
            let sampleFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)
            let state = self.state
            let node = AVAudioSourceNode(format: sampleFormat!) { _, _, frameCount, audioBufferList -> OSStatus in
                state.render(frameCount: Int(frameCount), into: UnsafeMutableAudioBufferListPointer(audioBufferList))
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: sampleFormat)
            source = node
        }
        if !engine.isRunning {
            #if os(iOS)
            // Mixes with other audio, and keeps playing with the screen locked mid-session.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            try engine.start()
        }
    }

    private static func code(for sound: FocusSound) -> Int {
        switch sound {
        case .off, .white: 0
        case .pink: 1
        case .brown: 2
        }
    }
}

/// Noise state shared with the render thread. Only plain stored values, read and written without
/// locks: a torn read of the target gain or kind is harmless, since gain is smoothed per sample.
private final class NoiseState: @unchecked Sendable {
    final class Value<T>: @unchecked Sendable {
        private var value: T
        init(_ value: T) { self.value = value }
        func store(_ newValue: T) { value = newValue }
        func load() -> T { value }
    }

    let kind = Value(0)
    let targetGain = Value<Float>(0)
    private var gain: Float = 0
    private var seed: UInt32 = 0x9E37_79B9
    private var pink = (b0: Float(0), b1: Float(0), b2: Float(0), b3: Float(0), b4: Float(0), b5: Float(0), b6: Float(0))
    private var brown: Float = 0

    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let kind = self.kind.load()
        let target = targetGain.load()
        for buffer in buffers {
            guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for frame in 0..<frameCount {
                gain += (target - gain) * 0.0005
                samples[frame] = next(kind) * gain
            }
        }
    }

    /// One sample of noise in about -1...1.
    private func next(_ kind: Int) -> Float {
        // xorshift32: fast and allocation-free.
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        let white = Float(seed) / Float(UInt32.max) * 2 - 1
        switch kind {
        case 1:
            pink.b0 = 0.99886 * pink.b0 + white * 0.0555179
            pink.b1 = 0.99332 * pink.b1 + white * 0.0750759
            pink.b2 = 0.96900 * pink.b2 + white * 0.1538520
            pink.b3 = 0.86650 * pink.b3 + white * 0.3104856
            pink.b4 = 0.55000 * pink.b4 + white * 0.5329522
            pink.b5 = -0.7616 * pink.b5 - white * 0.0168980
            let value = pink.b0 + pink.b1 + pink.b2 + pink.b3 + pink.b4 + pink.b5 + pink.b6 + white * 0.5362
            pink.b6 = white * 0.115926
            return value * 0.11
        case 2:
            brown = (brown + 0.02 * white) / 1.02
            return brown * 3.5
        default:
            return white * 0.5
        }
    }
}
