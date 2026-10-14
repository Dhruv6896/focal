#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `Focal --preview [--settings]` shows the timer panel as an ordinary app window
/// (with sample stats) so the real rendering can be inspected and clicked through.
@MainActor
enum DebugPreview {
    private static var window: NSWindow?

    /// `Focal --app` (debug builds): runs the whole app as a regular app with sample
    /// stats, so the floating timer and break screen can be inspected. Returns true if
    /// that mode is on.
    static func prepareFullApp() -> Bool {
        guard CommandLine.arguments.contains("--app") else { return false }
        let prefs = Preferences()
        if prefs.todaySessions == 0 {
            prefs.logFocusSession(seconds: 50 * 60, task: "quarterly report")
            prefs.logFocusSession(seconds: 25 * 60, task: "inbox zero")
            prefs.logFocusSession(seconds: 25 * 60, task: "Quarterly report")
            prefs.logFocusSession(seconds: 15 * 60)
        }
        return true
    }

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--preview") else { return false }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let prefs = Preferences()
        prefs.volume = 0
        if prefs.todaySessions == 0 {
            prefs.logFocusSession(seconds: 25 * 60)
            prefs.logFocusSession(seconds: 25 * 60)
            prefs.logFocusSession(seconds: 25 * 60)
            prefs.task = "quarterly report"
            prefs.noteTaskUsed("inbox zero")
            prefs.noteTaskUsed("quarterly report")
        }
        let timer = TimerModel(prefs: prefs, alarm: AlarmPlayer())
        let presentation = PanelPresentation()
        presentation.shown = true

        let hosting = NSHostingView(rootView: TimerPanelView(
            timer: timer, prefs: prefs, presentation: presentation,
            onMore: { presentation.showingWeek.toggle() }
        ))
        let panel = TimerPanel(size: TimerPanelView.size)
        panel.install(hosting, cornerRadius: TimerPanelView.cornerRadius)
        panel.isMovableByWindowBackground = true
        panel.level = .normal
        panel.title = "Focal Preview"
        panel.center()
        // Key and active, like the real panel when opened from the menu bar.
        app.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        window = panel

        if CommandLine.arguments.contains("--settings") {
            let settingsHost = NSHostingController(rootView: SettingsView(prefs: prefs, alarm: AlarmPlayer()))
            settingsHost.sizingOptions = .preferredContentSize
            let settings = NSWindow(contentViewController: settingsHost)
            settings.styleMask = [.titled, .closable, .fullSizeContentView]
            settings.titlebarAppearsTransparent = true
            settings.titleVisibility = .hidden
            settings.title = "Focal Settings"
            settings.center()
            settings.orderFrontRegardless()
            objc_setAssociatedObject(app, "previewSettings", settings, .OBJC_ASSOCIATION_RETAIN)
        }

        let sound = FocusSoundPlayer()
        sound.update(sound: prefs.focusSound, volume: prefs.focusSoundVolume,
                     playing: timer.state == .running && timer.mode == .focus)
        objc_setAssociatedObject(app, "previewSound", sound, .OBJC_ASSOCIATION_RETAIN)

        // Keep a reference so the model lives for the whole run.
        objc_setAssociatedObject(app, "previewTimer", timer, .OBJC_ASSOCIATION_RETAIN)
        app.run()
        return true
    }
}
#endif
