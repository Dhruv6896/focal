import AppKit

/// Plays the alarm chime on repeat until stopped (or until the auto-stop limit).
@MainActor
final class AlarmPlayer {
    private var repeatTimer: Timer?
    private var stopTimer: Timer?
    private var current: NSSound?

    private(set) var isRinging = false

    /// Names of the built-in macOS alert sounds.
    static let availableSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let names = files.filter { $0.hasSuffix(".aiff") }.map { ($0 as NSString).deletingPathExtension }.sorted()
        return names.isEmpty ? ["Glass"] : names
    }()

    func ring(sound: String, volume: Double, stopAfter seconds: TimeInterval) {
        stop()
        guard volume > 0 else { return }
        isRinging = true
        playOnce(sound: sound, volume: volume)

        let repeatTimer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.playOnce(sound: sound, volume: volume) }
        }
        let stopTimer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        RunLoop.main.add(repeatTimer, forMode: .common)
        RunLoop.main.add(stopTimer, forMode: .common)
        self.repeatTimer = repeatTimer
        self.stopTimer = stopTimer
    }

    /// Plays a single chime, used when adjusting the volume slider.
    func preview(sound: String, volume: Double) {
        stop()
        playOnce(sound: sound, volume: volume)
    }

    func stop() {
        isRinging = false
        repeatTimer?.invalidate()
        stopTimer?.invalidate()
        repeatTimer = nil
        stopTimer = nil
        current?.stop()
        current = nil
    }

    private func playOnce(sound name: String, volume: Double) {
        guard let sound = (NSSound(named: name) ?? NSSound(named: "Glass"))?.copy() as? NSSound else { return }
        sound.volume = Float(volume)
        sound.play()
        current = sound
    }
}
