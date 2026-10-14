import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@main
enum FocalMain {
    @MainActor static func main() {
        #if DEBUG
        if DebugShowcase.runIfRequested() { return }
        if DebugPreview.runIfRequested() { return }
        let policy: NSApplication.ActivationPolicy = DebugPreview.prepareFullApp() ? .regular : .accessory
        #else
        let policy = NSApplication.ActivationPolicy.accessory
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(policy)
        app.run()
    }
}

/// Borderless panel that drops down from the menu bar pill.
final class TimerPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        // No window shadow: the system computes it from the window's rectangular
        // bounds behind the glass, which shows up as a dark square frame.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }

    /// Installs the content, clipped to the panel's rounded shape so nothing
    /// (glass backdrop included) bleeds into the corners.
    func install(_ content: NSView, cornerRadius: CGFloat) {
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let prefs = Preferences()
    private let alarm = AlarmPlayer()
    private lazy var timer = TimerModel(prefs: prefs, alarm: alarm)
    private let presentation = PanelPresentation()
    private let focusSound = FocusSoundPlayer()
    private lazy var miniTimer = MiniTimerController(timer: timer, prefs: prefs) { [weak self] in
        self?.showPanel(activate: true)
    }
    private lazy var breakScreen = BreakScreenController(timer: timer, prefs: prefs)

    private var statusItem: NSStatusItem!
    private var panel: TimerPanel?
    private var settingsWindow: NSWindow?
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0
    private var lastPanelClose = Date.distantPast
    private var panelOpen = false
    private var pendingOrderOut: DispatchWorkItem?

    private var blinkTimer: Timer?
    private var blinkOn = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        timer.onFinish = { [weak self] in self?.timerFinished() }

        Publishers.Merge(timer.objectWillChange, prefs.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshStatusItem()
                self.miniTimer.update()
                self.breakScreen.update()
            }
            .store(in: &cancellables)

        timer.$state
            .removeDuplicates()
            .sink { [weak self] state in self?.updateBlinking(ringing: state == .ringing) }
            .store(in: &cancellables)

        // Background noise only while a focus session is actually counting down.
        Publishers.CombineLatest4(timer.$state, timer.$mode, prefs.$focusSound, prefs.$focusSoundVolume)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, mode, sound, volume in
                self?.focusSound.update(sound: sound, volume: volume, playing: state == .running && mode == .focus)
            }
            .store(in: &cancellables)

        // Run the user's Shortcuts when focus starts and ends (pausing doesn't count as
        // ending). Debounced so momentary in-between states don't fire anything.
        Publishers.CombineLatest(timer.$state, timer.$mode)
            .map { state, mode in mode == .focus && (state == .running || state == .paused) }
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] focusing in
                guard let self else { return }
                ShortcutsRunner.run(focusing ? self.prefs.shortcutOnFocusStart : self.prefs.shortcutOnFocusEnd)
            }
            .store(in: &cancellables)

        prefs.$globalShortcut
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setGlobalShortcut(enabled) }
            .store(in: &cancellables)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.prefs.pauseOnLock else { return }
                self.timer.screenLocked()
            }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.timer.screenUnlocked() }
        }

        installKeyMonitor()
        refreshStatusItem()
        miniTimer.update()
        breakScreen.update()
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        togglePanel()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let compact = prefs.iconStyle == .compact
        let contrast = prefs.increaseContrast
        let label: (Int) -> String = { compact ? TimeFormat.compact($0) : TimeFormat.clock($0) }

        let image: NSImage
        let dim: CGFloat = contrast ? 1 : 0.55
        if compact {
            switch timer.state {
            case .idle:
                image = StatusItemRenderer.ring(progress: 1, text: TimeFormat.compact(timer.duration), bold: contrast, alpha: dim)
            case .running:
                image = StatusItemRenderer.ring(progress: timer.sessionProgress, text: label(timer.remaining), bold: contrast)
            case .paused:
                image = StatusItemRenderer.ring(progress: timer.sessionProgress, text: label(timer.remaining), bold: contrast, alpha: dim)
            case .ringing:
                image = StatusItemRenderer.ring(progress: blinkOn ? 1 : 0, text: "0s", bold: contrast)
            }
        } else {
            // A cup in the pill tells breaks apart from focus at a glance.
            let symbol = timer.mode == .rest ? "cup.and.saucer.fill" : nil
            switch timer.state {
            case .idle:
                image = StatusItemRenderer.pill(TimeFormat.duration(timer.duration), style: .outlined, bold: contrast, alpha: dim)
            case .running:
                image = StatusItemRenderer.pill(label(timer.remaining), style: .filled, bold: contrast, symbol: symbol)
            case .paused:
                image = StatusItemRenderer.pill(label(timer.remaining), style: .outlined, bold: contrast, symbol: symbol)
            case .ringing:
                image = StatusItemRenderer.pill(label(0), style: blinkOn ? .filled : .outlined, bold: contrast)
            }
        }
        button.image = image

        let task = prefs.task.trimmingCharacters(in: .whitespacesAndNewlines)
        let left = "\(TimeFormat.clock(timer.remaining)) left"
        let ends = timer.endsAt.map { " · ends \(Self.clockTime.string(from: $0).lowercased())" } ?? ""
        switch (timer.state, timer.mode) {
        case (.idle, _): button.toolTip = "focal — \(TimeFormat.duration(timer.duration))"
        case (_, .rest): button.toolTip = "\(timer.isLongBreak ? "long break" : "break") · \(left)\(ends)"
        case (_, .focus): button.toolTip = (task.isEmpty ? "" : "\(task) · ") + left + ends
        }
        button.setAccessibilityLabel(button.toolTip)
    }

    private static let clockTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func updateBlinking(ringing: Bool) {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkOn = true
        guard ringing else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.blinkOn.toggle()
                self.refreshStatusItem()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func showContextMenu() {
        let menu = NSMenu()
        switch timer.state {
        case .idle:
            menu.addItem(menuItem("start \(TimeFormat.duration(timer.duration))", #selector(menuToggle)))
        case .running:
            menu.addItem(menuItem("pause", #selector(menuToggle)))
            menu.addItem(menuItem("cancel", #selector(menuCancel)))
        case .paused:
            menu.addItem(menuItem("resume", #selector(menuToggle)))
            menu.addItem(menuItem("cancel", #selector(menuCancel)))
        case .ringing:
            menu.addItem(menuItem("dismiss", #selector(menuCancel)))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("settings…", #selector(openSettings)))
        menu.addItem(menuItem("quit focal", #selector(quit)))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// The panel's "···" menu.
    private func showMoreMenu() {
        let menu = NSMenu()
        let week = menuItem(presentation.showingWeek ? "hide week" : "show week", #selector(toggleWeek))
        menu.addItem(week)
        menu.addItem(menuItem(prefs.floatingTimer == .off ? "show floating timer" : "hide floating timer",
                              #selector(toggleFloatingTimer)))
        menu.addItem(menuItem("settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("about focal", #selector(showAbout)))
        menu.addItem(menuItem("quit focal", #selector(quit)))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func toggleWeek() { presentation.showingWeek.toggle() }

    @objc private func toggleFloatingTimer() {
        prefs.floatingTimer = prefs.floatingTimer == .off ? .active : .off
    }

    private func showRecentTasksMenu() {
        let menu = NSMenu()
        for task in prefs.recentTasks {
            let item = NSMenuItem(title: task, action: #selector(pickRecentTask(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = task
            item.state = task == prefs.task ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if !prefs.task.isEmpty {
            menu.addItem(menuItem("clear task", #selector(clearTask)))
        }
        menu.addItem(menuItem("forget recent tasks", #selector(forgetRecentTasks)))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func pickRecentTask(_ sender: NSMenuItem) {
        if let task = sender.representedObject as? String { prefs.task = task }
    }

    @objc private func clearTask() { prefs.task = "" }
    @objc private func forgetRecentTasks() { prefs.clearRecentTasks() }
    @objc private func menuToggle() { timer.toggle() }
    @objc private func menuCancel() { timer.cancel() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showAbout() {
        closePanel()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        // Name, icon, version and the "Made by" line come from Info.plist.
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // MARK: - Panel

    private func togglePanel() {
        if panelOpen {
            closePanel()
        } else if Date().timeIntervalSince(lastPanelClose) > 0.25 {
            showPanel(activate: true)
        }
    }

    private func makePanel() -> TimerPanel {
        let view = TimerPanelView(
            timer: timer,
            prefs: prefs,
            presentation: presentation,
            onMore: { [weak self] in self?.showMoreMenu() },
            onRecentTasks: { [weak self] in self?.showRecentTasksMenu() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: TimerPanelView.size)
        let panel = TimerPanel(size: TimerPanelView.size)
        panel.install(hosting, cornerRadius: TimerPanelView.cornerRadius)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.closePanel() }
        return panel
    }

    private func showPanel(activate: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        prefs.rollOverDayIfNeeded()
        pendingOrderOut?.cancel()
        pendingOrderOut = nil
        if !panel.isVisible {
            presentation.shown = false
            presentation.showingWeek = false
        }
        panelOpen = true
        positionPanel(panel)

        if activate {
            // Opening the panel by hand acknowledges the alarm.
            if timer.state == .ringing { timer.silence() }
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            panel.makeKeyAndOrderFront(nil)
            // Keep keyboard shortcuts working instead of focusing the task field.
            DispatchQueue.main.async { panel.makeFirstResponder(nil) }
        } else {
            panel.orderFrontRegardless()
        }
        // Spring the glass in on the next pass, once the window is on screen.
        DispatchQueue.main.async { self.presentation.shown = true }
        installOutsideClickMonitor()
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let buttonWindow = statusItem.button?.window else { return }
        let anchor = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main
        let size = panel.frame.size
        var x = anchor.minX
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: anchor.minY - size.height - 6))
    }

    private func closePanel() {
        guard let panel, panelOpen else { return }
        panelOpen = false
        panel.makeFirstResponder(nil)
        presentation.shown = false
        lastPanelClose = Date()
        removeOutsideClickMonitor()

        let orderOut = DispatchWorkItem { [weak self] in
            panel.orderOut(nil)
            self?.presentation.showingWeek = false
        }
        pendingOrderOut = orderOut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: orderOut)
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel {
            closePanel()
        }
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func timerFinished() {
        refreshStatusItem()
        if prefs.showPanelOnFinish && !panelOpen {
            // Show without stealing focus from whatever you're typing in.
            showPanel(activate: false)
        }
    }

    // MARK: - Keyboard

    /// space start/pause · ←/→ ±1 min (⇧ ±5) · 1/2/3 presets · w week · f floating timer
    /// return dismiss · esc close
    /// ⌘, settings · ⌘W close · ⌘Q quit
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel, event.window === panel else { return false }
                return self.handlePanelKey(event, in: panel)
            }
            return handled ? nil : event
        }

        // Scrolling over the panel adjusts the length while the timer is idle.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel, event.window === panel else { return false }
                return self.handlePanelScroll(event)
            }
            return handled ? nil : event
        }
    }

    private func handlePanelScroll(_ event: NSEvent) -> Bool {
        guard timer.state == .idle, !presentation.showingWeek else { return false }
        // Up/right means more time, whatever the natural-scrolling setting.
        let vertical = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let horizontal = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal
        if event.phase == .began { scrollAccumulator = 0 }

        // Trackpads report pixels; mouse wheels report whole lines.
        scrollAccumulator += event.hasPreciseScrollingDeltas ? delta / 14 : delta
        let steps = Int(scrollAccumulator.rounded(.towardZero))
        guard steps != 0 else { return true }
        scrollAccumulator -= CGFloat(steps)
        timer.nudge(minutes: steps)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        return true
    }

    private func handlePanelKey(_ event: NSEvent, in panel: NSPanel) -> Bool {
        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // While typing in the task field, only use return/esc to leave it.
        if panel.firstResponder is NSText {
            if keyCode == kVK_Return || keyCode == kVK_Escape {
                panel.makeFirstResponder(nil)
                return true
            }
            return false
        }

        if modifiers.subtracting([.function, .numericPad]) == .command {
            switch event.charactersIgnoringModifiers {
            case ",": openSettings()
            case "w": closePanel()
            case "q": NSApp.terminate(nil)
            default: return false
            }
            return true
        }

        guard modifiers.subtracting([.shift, .function, .numericPad]).isEmpty else { return false }
        let step = modifiers.contains(.shift) ? 5 : 1

        switch keyCode {
        case kVK_Space:
            timer.toggle()
        case kVK_Escape:
            if presentation.showingWeek { presentation.showingWeek = false } else { closePanel() }
        case kVK_ANSI_W:
            presentation.showingWeek.toggle()
        case kVK_ANSI_F:
            toggleFloatingTimer()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if timer.state == .ringing { timer.cancel() } else { timer.toggle() }
        case kVK_LeftArrow:
            if timer.state != .ringing { timer.nudge(minutes: -step) }
        case kVK_RightArrow:
            if timer.state != .ringing { timer.nudge(minutes: step) }
        default:
            guard let chars = event.charactersIgnoringModifiers,
                  let digit = Int(chars), (1...3).contains(digit) else { return false }
            timer.startPreset(minutes: prefs.presets[digit - 1])
        }
        return true
    }

    private func setGlobalShortcut(_ enabled: Bool) {
        hotKey?.unregister()
        hotKey = nil
        guard enabled else { return }
        hotKey = HotKey(keyCode: kVK_ANSI_P, modifiers: cmdKey | optionKey) { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Settings

    @objc private func openSettings() {
        closePanel()
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(prefs: prefs, alarm: alarm))
        // Let the window grow and shrink with the selected tab.
        hosting.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Focal Settings"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        return window
    }
}
