import AppKit
import SwiftUI

/// Dims every display during a break, with a glass card counting down on the main one.
/// "reminder" lets clicks through; "blocking" covers the screens until the break ends
/// or you skip it.
struct BreakOverlayView: View {
    @ObservedObject var timer: TimerModel
    let blocking: Bool
    let showsCard: Bool
    let tip: String
    var onSkip: () -> Void

    @StateObject private var appeared = LocalState(false)

    var body: some View {
        ZStack {
            Color.black.opacity(blocking ? 0.6 : 0.4)
            if showsCard {
                card
                    .scaleEffect(appeared.value ? 1 : 0.92)
                    .opacity(appeared.value ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) { appeared.value = true }
        }
    }

    private var card: some View {
        VStack(spacing: 6) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 26))
                .foregroundStyle(TimerPanelView.breakGreen)
                .padding(.bottom, 4)
            Text(timer.isLongBreak ? "long break" : "time to step away")
                .font(.system(size: 20, weight: .semibold))
            Text(TimeFormat.clock(timer.remaining))
                .font(.system(size: 72, weight: .light))
                .monospacedDigit()
                .opacity(timer.state == .paused ? 0.6 : 1)
            Text(tip)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
            if blocking {
                GlassChip(title: "skip break", systemImage: "forward.fill", action: onSkip)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 32)
        .modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: 32, style: .continuous)))
    }
}

enum BreakTips {
    static let short = [
        "look at something far away for 20 seconds",
        "roll your shoulders and stretch your neck",
        "stand up and refill your water",
        "close your eyes and take five slow breaths",
        "walk around the room",
        "stretch your wrists and fingers",
    ]
    static let long = [
        "go for a short walk",
        "get some fresh air and daylight",
        "have a snack and some water",
        "step away from every screen for a while",
    ]

    static func random(long: Bool) -> String {
        (long ? Self.long : short).randomElement() ?? ""
    }
}

@MainActor
final class BreakScreenController {
    private let timer: TimerModel
    private let prefs: Preferences
    private var windows: [NonKeyPanel] = []
    private var shownStyle: Preferences.BreakScreen = .off
    private var screenObserver: NSObjectProtocol?

    init(timer: TimerModel, prefs: Preferences) {
        self.timer = timer
        self.prefs = prefs
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Rebuild for the new display arrangement.
                guard let self, !self.windows.isEmpty else { return }
                self.removeWindows(animated: false)
                self.update()
            }
        }
    }

    func update() {
        let onBreak = timer.mode == .rest && (timer.state == .running || timer.state == .paused)
        let style = onBreak ? prefs.breakScreen : .off
        guard style != shownStyle || (style != .off && windows.isEmpty) else { return }
        removeWindows(animated: style == .off)
        shownStyle = style
        if style != .off { show(blocking: style == .blocking) }
    }

    /// Ends the break early (blocking style's "skip break").
    private func skip() {
        timer.skipBreak()
    }

    private func show(blocking: Bool) {
        let tip = BreakTips.random(long: timer.isLongBreak)
        let main = NSScreen.main ?? NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = NonKeyPanel(contentRect: screen.frame)
            // Blocking covers everything, menu bar included; the reminder sits under the
            // menu bar so the timer panel stays reachable.
            window.level = blocking ? .screenSaver : .floating
            window.ignoresMouseEvents = !blocking
            let view = BreakOverlayView(timer: timer, blocking: blocking, showsCard: screen == main, tip: tip,
                                        onSkip: { [weak self] in self?.skip() })
            window.contentView = FirstMouseHostingView(rootView: view)
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                window.animator().alphaValue = 1
            }
            windows.append(window)
        }
    }

    private func removeWindows(animated: Bool) {
        let closing = windows
        windows = []
        guard !closing.isEmpty else { return }
        guard animated else {
            closing.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
        })
    }
}
