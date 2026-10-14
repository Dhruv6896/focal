import Foundation
import ServiceManagement

/// User settings and today's focus stats, persisted in UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    enum IconStyle: String, CaseIterable {
        case compact, expanded
    }

    enum FocusSound: String, CaseIterable {
        case off, white, pink, brown
    }

    enum FloatingTimer: String, CaseIterable {
        /// `active` = while a timer is running or paused.
        case off, active, always
    }

    enum BreakScreen: String, CaseIterable {
        /// `reminder` dims the screens but lets clicks through; `blocking` covers them
        /// until the break ends or you skip it.
        case off, reminder, blocking
    }

    static let maxMinutes = 120

    private let defaults = UserDefaults.standard

    @Published var presets: [Int] { didSet { defaults.set(presets, forKey: Keys.presets) } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: Keys.volume) } }
    @Published var autoMute: Bool { didSet { defaults.set(autoMute, forKey: Keys.autoMute) } }
    @Published var iconStyle: IconStyle { didSet { defaults.set(iconStyle.rawValue, forKey: Keys.iconStyle) } }
    @Published var increaseContrast: Bool { didSet { defaults.set(increaseContrast, forKey: Keys.contrast) } }
    @Published var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: Keys.breakMinutes) } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Keys.longBreakMinutes) } }
    /// A long break follows every Nth focus session of the day (0 = never).
    @Published var longBreakEvery: Int { didSet { defaults.set(longBreakEvery, forKey: Keys.longBreakEvery) } }
    @Published var alarmSound: String { didSet { defaults.set(alarmSound, forKey: Keys.alarmSound) } }
    @Published var pauseOnLock: Bool { didSet { defaults.set(pauseOnLock, forKey: Keys.pauseOnLock) } }
    @Published var autoStartBreak: Bool { didSet { defaults.set(autoStartBreak, forKey: Keys.autoBreak) } }
    @Published var showPanelOnFinish: Bool { didSet { defaults.set(showPanelOnFinish, forKey: Keys.showOnFinish) } }
    @Published var globalShortcut: Bool { didSet { defaults.set(globalShortcut, forKey: Keys.globalShortcut) } }
    @Published var lastDuration: Int { didSet { defaults.set(lastDuration, forKey: Keys.lastDuration) } }
    @Published var task: String { didSet { defaults.set(task, forKey: Keys.task) } }
    /// Focus sessions to aim for each day (0 = no goal).
    @Published var dailyGoal: Int { didSet { defaults.set(dailyGoal, forKey: Keys.dailyGoal) } }
    @Published var autoStartFocus: Bool { didSet { defaults.set(autoStartFocus, forKey: Keys.autoFocus) } }
    @Published var focusSound: FocusSound { didSet { defaults.set(focusSound.rawValue, forKey: Keys.focusSound) } }
    @Published var focusSoundVolume: Double { didSet { defaults.set(focusSoundVolume, forKey: Keys.focusSoundVolume) } }
    /// Names of Shortcuts to run when focus starts / ends ("" = none).
    @Published var shortcutOnFocusStart: String { didSet { defaults.set(shortcutOnFocusStart, forKey: Keys.shortcutStart) } }
    @Published var shortcutOnFocusEnd: String { didSet { defaults.set(shortcutOnFocusEnd, forKey: Keys.shortcutEnd) } }
    @Published var floatingTimer: FloatingTimer { didSet { defaults.set(floatingTimer.rawValue, forKey: Keys.floatingTimer) } }
    /// Bottom-left corner of the floating timer in screen coordinates (nil = default spot).
    @Published var floatingTimerOrigin: CGPoint? {
        didSet {
            if let origin = floatingTimerOrigin {
                defaults.set([origin.x, origin.y], forKey: Keys.floatingOrigin)
            } else {
                defaults.removeObject(forKey: Keys.floatingOrigin)
            }
        }
    }
    @Published var breakScreen: BreakScreen { didSet { defaults.set(breakScreen.rawValue, forKey: Keys.breakScreen) } }
    /// Most recent first.
    @Published private(set) var recentTasks: [String] { didSet { defaults.set(recentTasks, forKey: Keys.recentTasks) } }

    @Published private(set) var launchAtLogin: Bool = false
    @Published private(set) var todaySessions: Int
    @Published private(set) var todayFocusSeconds: Int
    /// Focus seconds per day ("yyyy-MM-dd"), kept for the last few weeks.
    @Published private(set) var history: [String: Int]
    /// Focus seconds per day per task: ["yyyy-MM-dd": ["task": seconds]].
    @Published private(set) var taskHistory: [String: [String: Int]]
    private var statsDay: String

    private enum Keys {
        static let presets = "presets"
        static let volume = "alarmVolume"
        static let autoMute = "autoMute"
        static let iconStyle = "iconStyle"
        static let contrast = "increaseContrast"
        static let breakMinutes = "breakMinutes"
        static let longBreakMinutes = "longBreakMinutes"
        static let longBreakEvery = "longBreakEvery"
        static let alarmSound = "alarmSound"
        static let pauseOnLock = "pauseOnLock"
        static let history = "focusHistory"
        static let autoBreak = "autoStartBreak"
        static let showOnFinish = "showPanelOnFinish"
        static let globalShortcut = "globalShortcut"
        static let lastDuration = "lastDuration"
        static let task = "task"
        static let statsDay = "statsDay"
        static let sessions = "todaySessions"
        static let focusSeconds = "todayFocusSeconds"
        static let dailyGoal = "dailyGoal"
        static let autoFocus = "autoStartFocus"
        static let focusSound = "focusSound"
        static let focusSoundVolume = "focusSoundVolume"
        static let shortcutStart = "shortcutOnFocusStart"
        static let shortcutEnd = "shortcutOnFocusEnd"
        static let recentTasks = "recentTasks"
        static let floatingTimer = "floatingTimer"
        static let floatingOrigin = "floatingTimerOrigin"
        static let breakScreen = "breakScreen"
        static let taskHistory = "taskHistory"
    }

    init() {
        Self.migrateLegacySettings(into: defaults)
        defaults.register(defaults: [
            Keys.presets: [5, 10, 25],
            Keys.volume: 0.5,
            Keys.autoMute: false,
            Keys.iconStyle: IconStyle.expanded.rawValue,
            Keys.contrast: false,
            Keys.breakMinutes: 5,
            Keys.longBreakMinutes: 15,
            Keys.longBreakEvery: 4,
            Keys.alarmSound: "Glass",
            Keys.pauseOnLock: true,
            Keys.autoBreak: false,
            Keys.showOnFinish: true,
            Keys.globalShortcut: true,
            Keys.lastDuration: 25 * 60,
            Keys.task: "",
            Keys.dailyGoal: 8,
            Keys.autoFocus: false,
            Keys.focusSound: FocusSound.off.rawValue,
            Keys.focusSoundVolume: 0.35,
            Keys.shortcutStart: "",
            Keys.shortcutEnd: "",
            Keys.floatingTimer: FloatingTimer.active.rawValue,
            Keys.breakScreen: BreakScreen.reminder.rawValue,
        ])

        var storedPresets = (defaults.array(forKey: Keys.presets) as? [Int]) ?? [5, 10, 25]
        if storedPresets.count != 3 { storedPresets = [5, 10, 25] }
        presets = storedPresets
        volume = defaults.double(forKey: Keys.volume)
        autoMute = defaults.bool(forKey: Keys.autoMute)
        iconStyle = IconStyle(rawValue: defaults.string(forKey: Keys.iconStyle) ?? "") ?? .expanded
        increaseContrast = defaults.bool(forKey: Keys.contrast)
        breakMinutes = defaults.integer(forKey: Keys.breakMinutes)
        longBreakMinutes = defaults.integer(forKey: Keys.longBreakMinutes)
        longBreakEvery = defaults.integer(forKey: Keys.longBreakEvery)
        alarmSound = defaults.string(forKey: Keys.alarmSound) ?? "Glass"
        pauseOnLock = defaults.bool(forKey: Keys.pauseOnLock)
        autoStartBreak = defaults.bool(forKey: Keys.autoBreak)
        showPanelOnFinish = defaults.bool(forKey: Keys.showOnFinish)
        globalShortcut = defaults.bool(forKey: Keys.globalShortcut)
        lastDuration = defaults.integer(forKey: Keys.lastDuration)
        task = defaults.string(forKey: Keys.task) ?? ""
        dailyGoal = defaults.integer(forKey: Keys.dailyGoal)
        autoStartFocus = defaults.bool(forKey: Keys.autoFocus)
        focusSound = FocusSound(rawValue: defaults.string(forKey: Keys.focusSound) ?? "") ?? .off
        focusSoundVolume = defaults.double(forKey: Keys.focusSoundVolume)
        shortcutOnFocusStart = defaults.string(forKey: Keys.shortcutStart) ?? ""
        shortcutOnFocusEnd = defaults.string(forKey: Keys.shortcutEnd) ?? ""
        recentTasks = defaults.stringArray(forKey: Keys.recentTasks) ?? []
        floatingTimer = FloatingTimer(rawValue: defaults.string(forKey: Keys.floatingTimer) ?? "") ?? .active
        if let point = defaults.array(forKey: Keys.floatingOrigin) as? [Double], point.count == 2 {
            floatingTimerOrigin = CGPoint(x: point[0], y: point[1])
        } else {
            floatingTimerOrigin = nil
        }
        breakScreen = BreakScreen(rawValue: defaults.string(forKey: Keys.breakScreen) ?? "") ?? .reminder

        statsDay = defaults.string(forKey: Keys.statsDay) ?? ""
        todaySessions = defaults.integer(forKey: Keys.sessions)
        todayFocusSeconds = defaults.integer(forKey: Keys.focusSeconds)
        history = (defaults.dictionary(forKey: Keys.history) as? [String: Int]) ?? [:]
        taskHistory = (defaults.dictionary(forKey: Keys.taskHistory) as? [String: [String: Int]]) ?? [:]

        launchAtLogin = Self.loginItemEnabled
        rollOverDayIfNeeded()
    }

    /// The app used to be called "Pomodoro" (bundle id local.pomodoro.menubar). Carry its
    /// settings, stats and any running timer over the first time Focal launches.
    private static func migrateLegacySettings(into defaults: UserDefaults) {
        let flag = "migratedFromPomodoro"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        guard let legacy = defaults.persistentDomain(forName: "local.pomodoro.menubar") else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    // MARK: - Today's stats

    func logFocusSession(seconds: Int, task: String = "") {
        rollOverDayIfNeeded()
        todaySessions += 1
        todayFocusSeconds += seconds
        history[statsDay, default: 0] += seconds
        let task = task.trimmingCharacters(in: .whitespacesAndNewlines)
        taskHistory[statsDay, default: [:]][task, default: 0] += seconds
        saveStats()
    }

    /// Focus time per task over the last seven days, largest first. Untitled sessions use "".
    func lastSevenDaysByTask() -> [(task: String, seconds: Int)] {
        var totals: [String: Int] = [:]
        for day in lastSevenDays() {
            for (task, seconds) in taskHistory[Self.dayKey(for: day.date)] ?? [:] {
                // Merge differently-cased spellings of the same task.
                let key = totals.keys.first { $0.caseInsensitiveCompare(task) == .orderedSame } ?? task
                totals[key, default: 0] += seconds
            }
        }
        return totals.map { (task: $0.key, seconds: $0.value) }
            .filter { $0.seconds > 0 }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Remembers a task for the recent-tasks menu.
    func noteTaskUsed(_ task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentTasks = Array(([trimmed] + recentTasks.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }).prefix(6))
    }

    func clearRecentTasks() {
        recentTasks = []
    }

    /// Consecutive days with at least one finished focus session, ending today
    /// (or yesterday, so the streak doesn't look broken first thing in the morning).
    func streak() -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if (history[Self.dayKey(for: day)] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (history[Self.dayKey(for: day)] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The last seven days, oldest first, ending today.
    func lastSevenDays() -> [(date: Date, seconds: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date, history[Self.dayKey(for: date)] ?? 0)
        }
    }

    func rollOverDayIfNeeded() {
        let today = Self.dayKey()
        guard statsDay != today else { return }
        statsDay = today
        todaySessions = 0
        todayFocusSeconds = 0
        saveStats()
    }

    private func saveStats() {
        // Keep five weeks of history.
        if history.count > 35, let cutoff = Calendar.current.date(byAdding: .day, value: -35, to: Date()) {
            let oldest = Self.dayKey(for: cutoff)
            history = history.filter { $0.key >= oldest }
            taskHistory = taskHistory.filter { $0.key >= oldest }
        }
        defaults.set(history, forKey: Keys.history)
        defaults.set(taskHistory, forKey: Keys.taskHistory)
        defaults.set(statsDay, forKey: Keys.statsDay)
        defaults.set(todaySessions, forKey: Keys.sessions)
        defaults.set(todayFocusSeconds, forKey: Keys.focusSeconds)
    }

    private static func dayKey(for date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Launch at login

    private static var loginItemEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Focal: launch at login change failed: \(error.localizedDescription)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = Self.loginItemEnabled
    }
}

#if DEBUG
extension Preferences {
    /// Debug/showcase only: fills earlier days with sample focus time per task.
    /// `daysAgo` 1 = yesterday.
    func debugSeedHistory(_ days: [(daysAgo: Int, tasks: [(String, Int)])]) {
        let calendar = Calendar.current
        for day in days {
            guard let date = calendar.date(byAdding: .day, value: -day.daysAgo, to: Date()) else { continue }
            let key = Self.dayKey(for: date)
            history[key] = day.tasks.reduce(0) { $0 + $1.1 * 60 }
            taskHistory[key] = Dictionary(day.tasks.map { ($0.0, $0.1 * 60) }, uniquingKeysWith: +)
        }
    }
}
#endif
