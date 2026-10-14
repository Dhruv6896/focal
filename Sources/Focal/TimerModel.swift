import Foundation

/// Countdown state machine. Time is tracked against an end date, so it stays
/// accurate across sleep and run-loop hiccups.
@MainActor
final class TimerModel: ObservableObject {
    enum State { case idle, running, paused, ringing }
    enum Mode { case focus, rest }

    @Published private(set) var state: State = .idle
    @Published private(set) var mode: Mode = .focus
    /// Selected focus length in seconds.
    @Published private(set) var duration: Int
    /// Whole seconds left, rounded up (so a 25m timer shows 25:00 first and 00:00 at the end).
    @Published private(set) var remaining: Int
    /// Whether the current (or just finished) break is a long one.
    @Published private(set) var isLongBreak = false

    /// Called when a countdown reaches zero.
    var onFinish: (() -> Void)?

    private let prefs: Preferences
    private let alarm: AlarmPlayer
    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0
    /// Length of the current countdown, logged to today's stats when a focus session completes.
    private(set) var sessionLength = 0
    /// The task typed when the current focus session started; its time is logged against it.
    private var sessionTask = ""
    private var ticker: Timer?
    /// Set when the timer was paused automatically because the screen locked.
    private var pausedByLock = false

    static let maxSeconds = Preferences.maxMinutes * 60

    init(prefs: Preferences, alarm: AlarmPlayer) {
        self.prefs = prefs
        self.alarm = alarm
        let stored = prefs.lastDuration
        let initial = (60...Self.maxSeconds).contains(stored) ? stored : 25 * 60
        duration = initial
        remaining = initial
        restore()
    }

    // MARK: - Derived

    /// Indicator position on the ruler, 0...1.
    var rulerFraction: Double {
        switch state {
        case .idle: return Double(duration) / Double(Self.maxSeconds)
        case .running, .paused: return min(1, Double(remaining) / Double(Self.maxSeconds))
        case .ringing: return 0
        }
    }

    /// Fraction of the current countdown still left, 0...1.
    var sessionProgress: Double {
        switch state {
        case .idle: return 1
        case .ringing: return 0
        case .running, .paused:
            return sessionLength > 0 ? min(1, Double(remaining) / Double(sessionLength)) : 1
        }
    }

    /// When the running countdown will reach zero.
    var endsAt: Date? {
        state == .running ? endDate : nil
    }

    /// True when the next break should be a long one (every Nth session of the day).
    var nextBreakIsLong: Bool {
        prefs.longBreakEvery > 0 && prefs.todaySessions > 0 && prefs.todaySessions % prefs.longBreakEvery == 0
    }

    var nextBreakMinutes: Int {
        max(1, nextBreakIsLong ? prefs.longBreakMinutes : prefs.breakMinutes)
    }

    private var currentBreakSeconds: Int {
        max(1, isLongBreak ? prefs.longBreakMinutes : prefs.breakMinutes) * 60
    }

    // MARK: - Actions

    /// Sets the timer length from the ruler. Adjusts the live countdown if one is running.
    func setMinutes(_ minutes: Int) {
        let seconds = min(max(minutes, 1), Preferences.maxMinutes) * 60
        if mode == .focus || state == .idle || state == .ringing {
            duration = seconds
            prefs.lastDuration = seconds
        }
        switch state {
        case .idle:
            remaining = seconds
        case .running:
            endDate = Date().addingTimeInterval(TimeInterval(seconds))
            sessionLength = seconds
            remaining = seconds
            persist()
        case .paused:
            pausedRemaining = TimeInterval(seconds)
            sessionLength = seconds
            remaining = seconds
            persist()
        case .ringing:
            alarm.stop()
            mode = .focus
            state = .idle
            remaining = seconds
        }
    }

    func nudge(minutes delta: Int) {
        let current = state == .idle ? duration : remaining
        let minutes = Int((Double(current) / 60).rounded())
        setMinutes(minutes + delta)
    }

    func startPreset(minutes: Int) {
        mode = .focus
        state = .idle
        setMinutes(minutes)
        start()
    }

    /// Starts a focus session with the selected duration.
    func start() {
        mode = .focus
        sessionTask = prefs.task.trimmingCharacters(in: .whitespacesAndNewlines)
        prefs.noteTaskUsed(sessionTask)
        begin(seconds: duration)
    }

    func startBreak() {
        isLongBreak = nextBreakIsLong
        mode = .rest
        begin(seconds: currentBreakSeconds)
    }

    func restart() {
        if mode == .rest {
            begin(seconds: currentBreakSeconds)
        } else {
            start()
        }
    }

    func pause() {
        guard state == .running, let end = endDate else { return }
        pausedRemaining = max(0, end.timeIntervalSinceNow)
        remaining = Int(pausedRemaining.rounded(.up))
        state = .paused
        stopTicker()
        persist()
    }

    func resume() {
        guard state == .paused else { return }
        pausedByLock = false
        endDate = Date().addingTimeInterval(pausedRemaining)
        state = .running
        startTicker()
        persist()
    }

    /// Adds five minutes to a finished timer in the same mode.
    func snooze() {
        begin(seconds: 5 * 60)
    }

    /// Stops everything and returns to an idle focus timer.
    func cancel() {
        pausedByLock = false
        stopTicker()
        alarm.stop()
        endDate = nil
        mode = .focus
        state = .idle
        remaining = duration
        persist()
    }

    func toggle() {
        switch state {
        case .idle: start()
        case .running: pause()
        case .paused: resume()
        case .ringing: cancel()
        }
    }

    func silence() {
        alarm.stop()
    }

    /// Ends a break early: straight into focus on autopilot, otherwise back to idle.
    func skipBreak() {
        guard mode == .rest else { return }
        if prefs.autoStartFocus {
            start()
        } else {
            cancel()
        }
    }

    func screenLocked() {
        guard state == .running, mode == .focus else { return }
        pause()
        pausedByLock = true
    }

    func screenUnlocked() {
        if pausedByLock { resume() }
        pausedByLock = false
    }

    // MARK: - Ticking

    private func begin(seconds: Int) {
        alarm.stop()
        pausedByLock = false
        sessionLength = seconds
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        remaining = seconds
        state = .running
        startTicker()
        persist()
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard state == .running, let end = endDate else { return }
        let left = end.timeIntervalSinceNow
        if left <= 0 {
            finish()
            return
        }
        let rounded = Int(left.rounded(.up))
        if rounded != remaining { remaining = rounded }
    }

    #if DEBUG
    /// Showcase only: shows a running countdown frozen at `remaining` of `total` seconds.
    func debugFreezeRunning(remaining: Int, of total: Int) {
        stopTicker()
        sessionLength = total
        self.remaining = remaining
        endDate = Date().addingTimeInterval(TimeInterval(remaining))
        state = .running
    }
    #endif

    private func finish() {
        stopTicker()
        endDate = nil
        remaining = 0
        clearSaved()

        let finishedFocus = mode == .focus
        if finishedFocus {
            prefs.logFocusSession(seconds: sessionLength, task: sessionTask)
        }

        if finishedFocus && prefs.autoStartBreak {
            // Short chime, then roll straight into the break.
            startBreak()
            alarm.ring(sound: prefs.alarmSound, volume: prefs.volume, stopAfter: 3)
        } else if !finishedFocus && prefs.autoStartFocus {
            // Break's over: straight back into the next focus session.
            start()
            alarm.ring(sound: prefs.alarmSound, volume: prefs.volume, stopAfter: 3)
        } else {
            state = .ringing
            alarm.ring(sound: prefs.alarmSound, volume: prefs.volume, stopAfter: prefs.autoMute ? 5 : 60)
        }
        onFinish?()
    }

    // MARK: - Surviving relaunches

    private static let savedKey = "savedTimer"

    /// Saves a running or paused countdown so quitting, updating or a crash doesn't lose it.
    private func persist() {
        var saved: [String: Any] = [
            "mode": mode == .rest ? "rest" : "focus",
            "sessionLength": sessionLength,
            "isLongBreak": isLongBreak,
            "task": sessionTask,
        ]
        switch state {
        case .running:
            guard let endDate else { return clearSaved() }
            saved["state"] = "running"
            saved["endDate"] = endDate.timeIntervalSince1970
        case .paused:
            saved["state"] = "paused"
            saved["pausedRemaining"] = pausedRemaining
        case .idle, .ringing:
            return clearSaved()
        }
        UserDefaults.standard.set(saved, forKey: Self.savedKey)
    }

    private func clearSaved() {
        UserDefaults.standard.removeObject(forKey: Self.savedKey)
    }

    private func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.savedKey),
              let savedState = saved["state"] as? String else { return }
        mode = saved["mode"] as? String == "rest" ? .rest : .focus
        isLongBreak = saved["isLongBreak"] as? Bool ?? false
        sessionLength = saved["sessionLength"] as? Int ?? duration
        sessionTask = saved["task"] as? String ?? ""

        if savedState == "paused", let left = saved["pausedRemaining"] as? Double, left > 0 {
            pausedRemaining = left
            remaining = Int(left.rounded(.up))
            state = .paused
        } else if savedState == "running", let end = saved["endDate"] as? Double {
            let endDate = Date(timeIntervalSince1970: end)
            if endDate.timeIntervalSinceNow > 0 {
                self.endDate = endDate
                remaining = Int(endDate.timeIntervalSinceNow.rounded(.up))
                state = .running
                startTicker()
            } else {
                // It ran out while the app was closed: count it, but don't ring late.
                if mode == .focus { prefs.logFocusSession(seconds: sessionLength, task: sessionTask) }
                mode = .focus
                clearSaved()
            }
        } else {
            mode = .focus
            clearSaved()
        }
    }
}
