import AVFoundation

/// Generates white, pink or brown noise while a focus session runs. Everything is
/// synthesised on the fly, so there are no audio files to ship.
@MainActor
final class FocusSoundPlayer {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private let generator = NoiseGenerator()
    private var fadeTimer: Timer?
    private var targetVolume: Float = 0
    private var stopWhenSilent = false

    /// Starts, retunes or fades out the noise.
    func update(sound: Preferences.FocusSound, volume: Double, playing: Bool) {
        let shouldPlay = playing && sound != .off && volume > 0
        generator.kind = sound
        guard shouldPlay else {
            fade(to: 0, thenStop: true)
            return
        }
        if !engine.isRunning {
            guard start() else { return }
        }
        // Perceived loudness is roughly logarithmic; square the slider value.
        fade(to: Float(volume * volume), thenStop: false)
    }

    private func start() -> Bool {
        if source == nil {
            let output = engine.outputNode.inputFormat(forBus: 0)
            let sampleRate = output.sampleRate > 0 ? output.sampleRate : 44_100
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return false }
            let generator = self.generator
            let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
                let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    generator.fill(data, count: Int(frameCount))
                }
                return noErr
            }
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            source = node
        }
        engine.mainMixerNode.outputVolume = 0
        do {
            try engine.start()
            return true
        } catch {
            NSLog("Focal: focus sound failed to start: \(error.localizedDescription)")
            return false
        }
    }

    /// Ramps the volume over about a second so starting and stopping never clicks.
    private func fade(to volume: Float, thenStop: Bool) {
        targetVolume = volume
        stopWhenSilent = thenStop
        guard engine.isRunning, fadeTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeStep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func fadeStep() {
        let mixer = engine.mainMixerNode
        let current = mixer.outputVolume
        let step: Float = 1.0 / 30
        if abs(current - targetVolume) <= step {
            mixer.outputVolume = targetVolume
            fadeTimer?.invalidate()
            fadeTimer = nil
            if stopWhenSilent && targetVolume == 0 {
                engine.pause()
            }
        } else {
            mixer.outputVolume = current + (targetVolume > current ? step : -step)
        }
    }
}

/// Audio-thread noise source. Only ever touched by the render callback, apart from
/// `kind`, whose occasional unsynchronised write is harmless.
private final class NoiseGenerator: @unchecked Sendable {
    var kind: Preferences.FocusSound = .brown

    // Pink noise filter state (Paul Kellet's economy filter) and brown noise integrator.
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0
    private var brown: Float = 0
    private var seed: UInt32 = 0x2545_F491

    func fill(_ data: UnsafeMutablePointer<Float>, count: Int) {
        let kind = self.kind
        for i in 0..<count {
            let white = nextWhite()
            switch kind {
            case .off:
                data[i] = 0
            case .white:
                data[i] = white * 0.25
            case .pink:
                b0 = 0.99765 * b0 + white * 0.0990460
                b1 = 0.96300 * b1 + white * 0.2965164
                b2 = 0.57000 * b2 + white * 1.0526913
                data[i] = (b0 + b1 + b2 + white * 0.1848) * 0.11
            case .brown:
                brown = (brown + white * 0.02) / 1.02
                data[i] = brown * 2.8
            }
        }
    }

    /// Fast xorshift white noise in -1...1.
    private func nextWhite() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }
}
