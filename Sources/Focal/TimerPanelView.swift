import AppKit
import SwiftUI

/// Shared between the panel window and its SwiftUI content.
@MainActor
final class PanelPresentation: ObservableObject {
    /// Drives the open/close animation.
    @Published var shown = false
    @Published var showingWeek = false
    /// Week view shows time per task instead of per day (remembered while the app runs).
    @Published var weekByTask = false
}

struct TimerPanelView: View {
    @ObservedObject var timer: TimerModel
    @ObservedObject var prefs: Preferences
    @ObservedObject var presentation: PanelPresentation
    var onMore: () -> Void
    var onRecentTasks: () -> Void = {}

    @Namespace private var glassSpace

    static let size = CGSize(width: 460, height: 262)
    static let cornerRadius: CGFloat = 30
    static let focusRed = Color(red: 0.96, green: 0.30, blue: 0.24)
    static let breakGreen = Color(red: 0.20, green: 0.74, blue: 0.48)

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TickRuler(
                fraction: timer.rulerFraction,
                accent: timer.state == .idle ? .primary : accent,
                active: timer.state != .idle,
                visible: presentation.shown,
                onSelect: { timer.setMinutes($0) }
            )
            .frame(height: 30)
            // Animate jumps (presets, arrow keys, scrolling) but not the once-a-second
            // countdown: a spring restarting every second keeps the canvas redrawing.
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: timer.duration)

            HStack(spacing: 8) {
                actionChips
                Spacer(minLength: 8)
                statsChip
                moreButton
            }
            .padding(.top, 20)

            ZStack(alignment: .topLeading) {
                if presentation.showingWeek {
                    WeekChart(days: prefs.lastSevenDays(), tasks: prefs.lastSevenDaysByTask(),
                              streak: prefs.streak(), accent: Self.focusRed,
                              byTask: $presentation.weekByTask)
                        .transition(.opacity.combined(with: .offset(y: 12)))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        focusLine.padding(.top, 14)
                        Spacer(minLength: 0)
                        // The button's bottom edge sits on the digits' baseline, so the
                        // two read as one row and share the panel's bottom margin.
                        HStack(alignment: .bottom) {
                            primaryButton
                            Spacer()
                            clock
                                // Drop the empty descender space under the digits so the
                                // baseline, not the text box, sets the bottom margin.
                                .padding(.bottom, Self.clockDescender)
                                .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
                                // Cancel the digits' side bearing so they line up with
                                // the ··· button's edge.
                                .padding(.trailing, -2)
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: -8)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(EdgeInsets(top: 22, leading: 22, bottom: 22, trailing: 22))
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            PanelBackground(
                focusWash: timer.mode == .focus ? washStrength : 0,
                breakWash: timer.mode == .rest ? washStrength : 0,
                pulsing: timer.state == .ringing,
                pulseColor: accent,
                cornerRadius: Self.cornerRadius
            )
        )
        .animation(spring, value: timer.state)
        .animation(spring, value: timer.mode)
        .animation(spring, value: presentation.showingWeek)
        .scaleEffect(presentation.shown ? 1 : 0.88, anchor: .top)
        .opacity(presentation.shown ? 1 : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: presentation.shown)
    }

    // MARK: - Colors

    private var accent: Color {
        timer.mode == .rest ? Self.breakGreen : Self.focusRed
    }

    /// How strongly the panel is washed with the mode color.
    private var washStrength: Double {
        switch timer.state {
        case .idle: return 0
        case .paused: return 0.06
        case .running, .ringing: return 0.14
        }
    }

    // MARK: - Pieces

    private var actionChips: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 8) {
                switch timer.state {
                case .idle:
                    ForEach(Array(prefs.presets.enumerated()), id: \.offset) { index, minutes in
                        chip(TimeFormat.preset(minutes: minutes), id: index) {
                            timer.startPreset(minutes: minutes)
                        }
                        .help("start \(minutes) min  (\(index + 1))")
                    }
                case .running, .paused:
                    chip("cancel", systemImage: "xmark", id: 0) { timer.cancel() }
                    chip("restart", systemImage: "arrow.counterclockwise", id: 1) { timer.restart() }
                case .ringing:
                    if timer.mode == .focus {
                        let long = timer.nextBreakIsLong
                        chip("\(long ? "long break" : "break") \(TimeFormat.preset(minutes: timer.nextBreakMinutes))",
                             systemImage: "cup.and.saucer.fill", tint: Self.breakGreen, id: 0) { timer.startBreak() }
                    } else {
                        chip("focus \(TimeFormat.preset(minutes: timer.duration / 60))",
                             systemImage: "scope", tint: Self.focusRed, id: 0) { timer.start() }
                    }
                    chip("+5m", id: 1) { timer.snooze() }
                }
            }
        }
    }

    private func chip(_ title: String, systemImage: String? = nil, tint: Color? = nil, id: Int,
                      action: @escaping () -> Void) -> some View {
        GlassChip(title: title, systemImage: systemImage, tint: tint,
                  glassID: "chip\(id)", namespace: glassSpace, action: action)
    }

    private var primaryButton: some View {
        let (title, icon, tinted): (String, String, Bool) = {
            switch timer.state {
            case .idle: return ("start", "play.fill", true)
            case .running: return ("pause", "pause.fill", false)
            case .paused: return ("resume", "play.fill", true)
            case .ringing: return ("dismiss", "checkmark", false)
            }
        }()
        return GlassGroup {
            GlassChip(title: title, systemImage: icon, tint: tinted ? accent : nil, prominent: true, large: true,
                      glassID: "primary", namespace: glassSpace) { timer.toggle() }
        }
        .help("space")
    }

    private static let clockFontSize: CGFloat = 80
    /// Negative: the font's descent below the baseline.
    private static let clockDescender = NSFont.systemFont(ofSize: clockFontSize, weight: .light).descender

    private var clock: some View {
        Text(TimeFormat.clock(timer.remaining))
            .font(.system(size: Self.clockFontSize, weight: .light))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            // Roll the digits on jumps only. The rolling effect is rendered on the CPU,
            // and animating every one-second tick kept it at 30–50% while the panel was open.
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: timer.duration)
            .foregroundStyle(.primary)
            .opacity(timer.state == .paused ? 0.7 : 1)
            .lineLimit(1)
            .fixedSize()
    }

    private var statsChip: some View {
        GlassGroup {
            GlassButton(tint: presentation.showingWeek ? Color.primary : nil, glassID: "stats", namespace: glassSpace,
                        action: { presentation.showingWeek.toggle() }) {
                HStack(spacing: 6) {
                    if presentation.showingWeek {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("week")
                    } else if prefs.dailyGoal > 0 {
                        GoalRing(done: prefs.todaySessions, goal: prefs.dailyGoal,
                                 color: Self.focusRed, metColor: Self.breakGreen)
                            .frame(width: 12, height: 12)
                        Text("\(prefs.todaySessions)/\(prefs.dailyGoal)")
                        Text(TimeFormat.total(prefs.todayFocusSeconds))
                            .foregroundStyle(.secondary)
                    } else {
                        if prefs.todaySessions > 0 {
                            HStack(spacing: 3) {
                                ForEach(0..<min(prefs.todaySessions, 6), id: \.self) { _ in
                                    Circle().fill(Self.focusRed).frame(width: 5, height: 5)
                                }
                            }
                        } else {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(TimeFormat.total(prefs.todayFocusSeconds))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .fixedSize()
            }
        }
        .help(statsHelp)
    }

    private var moreButton: some View {
        GlassGroup {
            GlassButton(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var statsHelp: String {
        let sessions = "\(prefs.todaySessions) session\(prefs.todaySessions == 1 ? "" : "s")"
        let goal = prefs.dailyGoal > 0 ? " of \(prefs.dailyGoal)" : ""
        return "\(sessions)\(goal) today · \(TimeFormat.total(prefs.todayFocusSeconds)) focused · click for the week  (w)"
    }

    private var focusLine: some View {
        HStack(spacing: 8) {
            if timer.mode == .rest {
                Label(restMessage, systemImage: "cup.and.saucer")
                    .foregroundStyle(Self.breakGreen)
                Spacer(minLength: 8)
            } else {
                Image(systemName: "pencil.line")
                    .foregroundStyle(.tertiary)
                TextField("what are you working on?", text: $prefs.task)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.secondary)
                if !prefs.recentTasks.isEmpty {
                    Button(action: onRecentTasks) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12, weight: .medium))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle(.tertiary)
                    .help("recent tasks")
                    .accessibilityLabel("recent tasks")
                }
            }
            if let status = statusLabel {
                Text(status)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .font(.system(size: 14))
    }

    /// Right-hand note: when the timer ends, that it's paused, or the round count.
    private var statusLabel: String? {
        switch timer.state {
        case .running:
            return timer.endsAt.map { "ends \(Self.clockTime.string(from: $0).lowercased())" }
        case .paused:
            return "paused"
        case .idle:
            return roundLabel
        case .ringing:
            return nil
        }
    }

    private static let clockTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private var restMessage: String {
        if timer.state == .ringing { return "break's over — ready for another round?" }
        return timer.isLongBreak ? "long break · go for a walk" : "break · step away from the screen"
    }

    /// "round 2/4" — where you are in the cycle before the next long break.
    private var roundLabel: String? {
        let every = prefs.longBreakEvery
        guard every > 0, timer.state != .ringing else { return nil }
        let done = prefs.todaySessions % every
        return "round \(done + 1)/\(every)"
    }
}

// MARK: - Background

private struct PanelBackground: View {
    var focusWash: Double
    var breakWash: Double
    var pulsing: Bool
    var pulseColor: Color
    var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if #available(macOS 26.0, *) {
                // Untinted glass plus separate color washes. Washes only animate their
                // opacity: interpolating between two translucent colors (or glass tints)
                // flashes fully saturated mid-transition.
                Color.clear.glassEffect(Glass.regular, in: shape)
            } else {
                shape.fill(scheme == .dark ? Color(white: 0.035) : Color(white: 0.968))
                shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.12), lineWidth: 1)
            }
            shape.fill(TimerPanelView.focusRed).opacity(focusWash)
                .allowsHitTesting(false)
            shape.fill(TimerPanelView.breakGreen).opacity(breakWash)
                .allowsHitTesting(false)
            // Gentle breathing glow while the alarm is up. The layer always exists and
            // just pauses: removing a per-frame view mid-animation flashes the glass.
            TimelineView(.animation(paused: !pulsing)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                shape.fill(pulseColor)
                    .opacity(pulsing ? 0.05 + 0.13 * (sin(t * 3.5) + 1) / 2 : 0)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Ruler

/// Tick layout on whole device pixels with a whole-pixel pitch, so every tick renders
/// identically (no shimmer on 1x displays). The marker always sits exactly on a tick.
private struct TickGrid {
    let width: CGFloat
    let pixel: CGFloat
    let step: CGFloat
    let count: Int
    let inset: CGFloat

    init(width: CGFloat, scale: CGFloat) {
        let scale = max(scale, 1)
        self.width = width
        pixel = 1 / scale
        step = (2.5 * scale).rounded(.up) / scale
        count = max(Int(width / step) + 1, 2)
        inset = (((width - CGFloat(count - 1) * step) / 2) * scale).rounded() / scale
    }

    /// Left edge of tick `index`.
    func x(_ index: Int) -> CGFloat { inset + CGFloat(index) * step }

    func nearestIndex(to x: CGFloat) -> Int {
        min(max(Int(((x - inset) / step).rounded()), 0), count - 1)
    }

    /// Index of the tick closest to `fraction` of the full range.
    func index(forFraction fraction: Double) -> Int {
        nearestIndex(to: CGFloat(fraction) * width)
    }

    /// Centre of tick `index` (ticks are one pixel wide).
    func center(_ index: Int) -> CGFloat { x(index) + pixel / 2 }
}

/// Dense tick strip. Click, drag or scroll to pick a length (1–120 minutes). Ticks up to
/// the marker are lit, so it reads as a progress bar while the timer runs. On macOS 26
/// the marker is a small lens of glass.
struct TickRuler: View, Animatable {
    var fraction: Double
    var accent: Color
    var active: Bool
    /// False while the panel is hidden; clears any leftover hover line.
    var visible: Bool = true
    var onSelect: (Int) -> Void

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    @StateObject private var hover = LocalState<CGFloat?>(nil)
    @StateObject private var lastMinute = LocalState<Int?>(nil)
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale

    private static let markerWidth: CGFloat = 14
    /// How far the glass marker reaches above and below the ticks.
    private static let markerOverhang: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let grid = TickGrid(width: size.width, scale: displayScale)
            let markerIndex = grid.index(forFraction: fraction)
            let hoverMinute = visible ? hover.value.map { minutes(at: $0, width: size.width) } : nil
            let hoverIndex = hoverMinute.map { grid.index(forFraction: Double($0) / Double(Preferences.maxMinutes)) }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, canvasSize in
                    let dim = Color.primary.opacity(scheme == .dark ? 0.28 : 0.2)
                    let quarter = Color.primary.opacity(scheme == .dark ? 0.55 : 0.45)
                    let lit = active ? accent.opacity(0.9) : Color.primary.opacity(0.6)
                    let quarters = quarterHourTicks(grid)
                    for i in 0..<grid.count {
                        let rect = CGRect(x: grid.x(i), y: 0, width: grid.pixel, height: canvasSize.height)
                        let color = i <= markerIndex ? lit : (quarters.contains(i) ? quarter : dim)
                        ctx.fill(Path(rect), with: .color(color))
                    }
                    if let hoverIndex, abs(hoverIndex - markerIndex) > 1 {
                        let x = grid.center(hoverIndex)
                        ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: canvasSize.height)),
                                 with: .color(.primary.opacity(0.4)))
                    }
                }

                marker(height: size.height)
                    .position(x: grid.center(markerIndex), y: size.height / 2)
                    .allowsHitTesting(false)
            }
            .onChange(of: visible) { isVisible in
                if !isVisible { hover.value = nil }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hover.value = value.location.x
                        let minute = minutes(at: value.location.x, width: size.width)
                        guard minute != lastMinute.value else { return }
                        lastMinute.value = minute
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        // Follow the pointer directly instead of springing after it.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { onSelect(minute) }
                    }
                    .onEnded { _ in lastMinute.value = nil }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hover.value = location.x
                case .ended: hover.value = nil
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(active ? "time left" : "timer length")
        .accessibilityValue(TimeFormat.preset(minutes: currentMinute))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSelect(min(currentMinute + 1, Preferences.maxMinutes))
            case .decrement: onSelect(max(currentMinute - 1, 1))
            @unknown default: break
            }
        }
    }

    private var currentMinute: Int {
        max(1, Int((fraction * Double(Preferences.maxMinutes)).rounded()))
    }

    @ViewBuilder
    private func marker(height: CGFloat) -> some View {
        let line = Capsule().fill(accent).frame(width: 2, height: height)
        let lensHeight = height + Self.markerOverhang * 2
        if #available(macOS 26.0, *) {
            ZStack {
                Color.clear
                    .frame(width: Self.markerWidth, height: lensHeight)
                    .glassEffect(Glass.clear, in: Capsule())
                line
            }
            .frame(width: Self.markerWidth, height: lensHeight)
        } else {
            line.frame(width: Self.markerWidth, height: lensHeight)
        }
    }

    /// Ticks nearest each 15-minute mark, drawn a little brighter as a scale.
    private func quarterHourTicks(_ grid: TickGrid) -> Set<Int> {
        let max = Preferences.maxMinutes
        return Set(stride(from: 15, to: max, by: 15).map {
            grid.index(forFraction: Double($0) / Double(max))
        })
    }

    private func minutes(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let raw = Double(x / width) * Double(Preferences.maxMinutes)
        return min(max(Int(raw.rounded()), 1), Preferences.maxMinutes)
    }
}

// MARK: - Week chart

private struct WeekChart: View {
    let days: [(date: Date, seconds: Int)]
    let tasks: [(task: String, seconds: Int)]
    let streak: Int
    let accent: Color
    @Binding var byTask: Bool

    @StateObject private var grown = LocalState(false)

    var body: some View {
        let total = days.reduce(0) { $0 + $1.seconds }
        let activeDays = days.filter { $0.seconds > 0 }.count

        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    viewToggle("by day", selected: !byTask) { byTask = false }
                    viewToggle("by task", selected: byTask) { byTask = true }
                }
                .padding(.bottom, 2)
                Text(TimeFormat.total(total))
                    .font(.system(size: 50, weight: .light))
                    .monospacedDigit()
                Text(activeDays > 0
                     ? "last 7 days · \(TimeFormat.total(total / activeDays)) avg"
                       + (streak > 1 ? " · \(streak)-day streak" : "")
                     : "finish a session to start your week")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .fixedSize()
            Spacer(minLength: 12)
            if byTask {
                taskBreakdown
                    .transition(.opacity)
            } else {
                dayBars
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: byTask)
        .padding(.top, 16)
        .padding(.bottom, 2)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .onAppear { grown.value = true }
    }

    private func viewToggle(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .tertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var dayBars: some View {
        let peak = max(days.map(\.seconds).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 11) {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                let isToday = index == days.count - 1
                VStack(spacing: 6) {
                    Capsule()
                        .fill(isToday ? accent : Color.primary.opacity(day.seconds > 0 ? 0.4 : 0.12))
                        .frame(width: 12, height: grown.value ? max(6, 88 * CGFloat(day.seconds) / CGFloat(peak)) : 6)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.03),
                                   value: grown.value)
                    Text(Self.letter(for: day.date))
                        .font(.system(size: 11, weight: isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .help("\(Self.weekday(for: day.date)) · \(TimeFormat.total(day.seconds))")
            }
        }
    }

    /// Where the week's focus time went, top tasks first.
    @ViewBuilder
    private var taskBreakdown: some View {
        if tasks.isEmpty {
            Text("name your sessions to see\nwhere the time goes")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .padding(.bottom, 4)
        } else {
            let shown = Array(tasks.prefix(4))
            let peak = max(shown.first?.seconds ?? 1, 1)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shown.indices, id: \.self) { index in
                    let item = shown[index]
                    HStack(spacing: 8) {
                        Text(item.task.isEmpty ? "untitled" : item.task)
                            .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(item.task.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Capsule()
                            .fill(index == 0 ? accent : Color.primary.opacity(0.4))
                            .frame(width: max(4, 40 * CGFloat(item.seconds) / CGFloat(peak)), height: 6)
                            .frame(width: 40, alignment: .leading)
                        Text(TimeFormat.total(item.seconds))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    .help("\(item.task.isEmpty ? "untitled" : item.task) · \(TimeFormat.total(item.seconds))")
                }
                if tasks.count > shown.count {
                    Text("+ \(tasks.count - shown.count) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            // Shrinks rather than overflowing when the week's total is wide.
            .frame(minWidth: 170, maxWidth: 240)
            .padding(.bottom, 2)
        }
    }

    private static func letter(for date: Date) -> String {
        String(weekday(for: date).prefix(1))
    }

    private static func weekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).lowercased()
    }
}

// MARK: - Goal ring

/// Small progress ring for today's sessions against the daily goal.
private struct GoalRing: View {
    let done: Int
    let goal: Int
    let color: Color
    let metColor: Color

    var body: some View {
        let progress = goal > 0 ? min(1, Double(done) / Double(goal)) : 0
        ZStack {
            Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(done >= goal ? metColor : color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
    }
}
