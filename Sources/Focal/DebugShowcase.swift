#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `Focal --showcase <scene> --wallpaper <png>` opens one 1200×675
/// window that composes the real views (Liquid Glass included) over a wallpaper, with a
/// mock menu bar and captions — ready-made images for the README and social posts.
/// Everything sits in one window so the glass has the wallpaper to refract and a
/// single-window capture shows the true look. Scenes: hero, week, break, settings.
@MainActor
enum DebugShowcase {
    static let size = CGSize(width: 1200, height: 675)
    private static var keepAlive: [AnyObject] = []

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--showcase") else { return false }
        let scene = index + 1 < args.count ? args[index + 1] : "hero"
        let wallpaper = args.firstIndex(of: "--wallpaper").flatMap { i in
            i + 1 < args.count ? NSImage(contentsOfFile: args[i + 1]) : nil
        } ?? NSImage(size: size)

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let prefs = Preferences()
        prefs.volume = 0
        prefs.focusSound = .off
        prefs.dailyGoal = 8
        if prefs.todaySessions == 0 {
            prefs.debugSeedHistory([
                (6, [("launch post", 50), ("design review", 25)]),
                (5, [("launch post", 75), ("reading", 50)]),
                (3, [("design review", 100), ("inbox zero", 50)]),
                (2, [("launch post", 75), ("reading", 25)]),
                (1, [("launch post", 100), ("design review", 50), ("inbox zero", 25)]),
            ])
            prefs.logFocusSession(seconds: 50 * 60, task: "launch post")
            prefs.logFocusSession(seconds: 25 * 60, task: "design review")
            prefs.logFocusSession(seconds: 25 * 60, task: "launch post")
            prefs.logFocusSession(seconds: 25 * 60, task: "inbox zero")
            prefs.logFocusSession(seconds: 25 * 60, task: "launch post")
        }
        prefs.task = "write the launch post"
        prefs.noteTaskUsed("design review")
        prefs.noteTaskUsed("write the launch post")
        let timer = TimerModel(prefs: prefs, alarm: AlarmPlayer())
        let presentation = PanelPresentation()
        presentation.shown = true

        let content: AnyView
        switch scene {
        case "week":
            timer.setMinutes(25)
            presentation.showingWeek = true
            presentation.weekByTask = true
            content = AnyView(FeatureScene(
                title: "See where your\nweek went",
                subtitle: "Daily goal, streaks and focus time per task — logged automatically from what you type.",
                trailing: AnyView(panel(timer, prefs, presentation))
            ))
        case "break":
            timer.startBreak()
            timer.debugFreezeRunning(remaining: 4 * 60 + 12, of: 5 * 60)
            content = AnyView(ZStack(alignment: .top) {
                BreakOverlayView(timer: timer, blocking: true, showsCard: true,
                                 tip: "roll your shoulders and stretch your neck", onSkip: {})
                    .frame(width: size.width, height: size.height)
                VStack(spacing: 12) {
                    Text("Breaks that actually happen")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Your screens dim with a countdown and a tip — or stay covered until the break is over.")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.top, 58)
            }
            .frame(width: size.width, height: size.height)
            .clipped())
        case "settings":
            content = AnyView(FeatureScene(
                title: "Make it yours",
                subtitle: "Focus sounds, long breaks, a daily goal, and Shortcuts that run when focus starts and ends.",
                trailing: AnyView(SettingsMock(prefs: prefs))
            ))
        default:
            timer.setMinutes(25)
            timer.start()
            timer.debugFreezeRunning(remaining: 18 * 60 + 24, of: 25 * 60)
            content = AnyView(HeroScene(timer: timer, panel: AnyView(panel(timer, prefs, presentation))))
        }

        let stage = Stage(wallpaper: wallpaper) { content }
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let window = NSWindow(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                                  width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Focal Showcase"
        window.contentView = NSHostingView(rootView: stage)
        app.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        keepAlive = [window, timer, prefs, presentation]
        app.run()
        return true
    }

    private static func panel(_ timer: TimerModel, _ prefs: Preferences, _ presentation: PanelPresentation) -> some View {
        TimerPanelView(timer: timer, prefs: prefs, presentation: presentation, onMore: {})
            .frame(width: TimerPanelView.size.width, height: TimerPanelView.size.height)
            .clipShape(RoundedRectangle(cornerRadius: TimerPanelView.cornerRadius, style: .continuous))
    }
}

// MARK: - Scenes

private struct Stage<Content: View>: View {
    let wallpaper: NSImage
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: wallpaper)
                .resizable()
                .frame(width: DebugShowcase.size.width, height: DebugShowcase.size.height)
            content
        }
        .frame(width: DebugShowcase.size.width, height: DebugShowcase.size.height, alignment: .topLeading)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

/// Menu bar with the Focal pill, the panel dropped down from it, the floating timer, and
/// the pitch on the left.
private struct HeroScene: View {
    @ObservedObject var timer: TimerModel
    let panel: AnyView
    private let pillX: CGFloat = 712

    var body: some View {
        ZStack(alignment: .topLeading) {
            MenuBarMock(timer: timer, pillX: pillX)

            panel.offset(x: pillX - 4, y: 38)

            MiniTimerView(timer: timer, onOpenPanel: {}, onHide: {})
                .clipShape(Capsule())
                .offset(x: 952, y: 590)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 84, height: 84)
                    Text("Focal")
                        .font(.system(size: 68, weight: .semibold))
                }
                Text("A liquid-glass focus timer\nthat lives in your menu bar.")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                Text("pomodoro cycles · break screen · focus sounds\nfloating timer · time per task · Shortcuts")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineSpacing(3)
                Text("free & open source  ·  made by Dhruv")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 12)
            }
            .foregroundStyle(.white)
            .offset(x: 70, y: 196)
        }
    }
}

private struct FeatureScene: View {
    let title: String
    let subtitle: String
    let trailing: AnyView

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Caption(title: title, subtitle: subtitle)
                .frame(width: 470, alignment: .leading)
                .padding(.leading, 70)
            Spacer(minLength: 0)
            trailing
                .padding(.trailing, 70)
        }
        .frame(width: DebugShowcase.size.width, height: DebugShowcase.size.height)
    }
}

private struct Caption: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 21))
                .foregroundStyle(.white.opacity(0.72))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                Text("Focal")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 14)
        }
    }
}

private struct MenuBarMock: View {
    @ObservedObject var timer: TimerModel
    let pillX: CGFloat

    /// Real time, so it agrees with the panel's "ends …" note.
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d  h:mm a"
        return formatter
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black.opacity(0.22))
                .frame(width: DebugShowcase.size.width, height: 30)
            HStack(spacing: 20) {
                Text("\u{F8FF}").font(.system(size: 15))
                Text("Finder").font(.system(size: 13, weight: .bold))
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
            }
            .padding(.leading, 20)
            .frame(height: 30)

            Image(nsImage: StatusItemRenderer.pill(TimeFormat.clock(timer.remaining), style: .filled, bold: false))
                .renderingMode(.template)
                .offset(x: pillX, y: 6.5)

            HStack(spacing: 18) {
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                Image(systemName: "magnifyingglass")
                Image(systemName: "switch.2")
                Text(Self.clock.string(from: Date()))
            }
            .offset(x: pillX + 86, y: 0)
            .frame(height: 30)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
    }
}

/// The settings window, drawn in place so it shares the wallpaper.
private struct SettingsMock: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        ZStack(alignment: .topLeading) {
            SettingsView(prefs: prefs, alarm: AlarmPlayer())
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                Circle().fill(Color(white: 0.4))
                Circle().fill(Color(white: 0.4))
            }
            .frame(width: 52, height: 12)
            .padding(.leading, 14)
            .padding(.top, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
    }
}
#endif
