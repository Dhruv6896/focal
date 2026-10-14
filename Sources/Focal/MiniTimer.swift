import AppKit
import SwiftUI

/// Hosting view that acts on the first click, so buttons in a window that isn't
/// key (the floating timer, the break screen) respond immediately.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Lets the whole floating timer be dragged with native window dragging; clicks
/// (on its button, double-clicks) still go through.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Borderless window that never takes keyboard focus, so clicking it doesn't pull
/// typing away from the app you're working in.
final class NonKeyPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View

/// Small glass pill with the time left. Stays on top (including over full-screen apps)
/// so the timer is visible when the menu bar isn't.
struct MiniTimerView: View {
    @ObservedObject var timer: TimerModel
    var onOpenPanel: () -> Void
    var onHide: () -> Void

    static let size = CGSize(width: 158, height: 46)

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: timer.state == .idle ? 0 : timer.sessionProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)

            Text(TimeFormat.clock(timer.remaining))
                .font(.system(size: 19, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .opacity(timer.state == .paused ? 0.6 : 1)

            Spacer(minLength: 0)

            // Clear glass with a coloured symbol: this window is never key, and macOS
            // greys out tinted glass in windows that aren't.
            GlassButton(action: { timer.toggle() }) {
                Image(systemName: buttonSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 28, height: 28)
            }
            .help(buttonHelp)
        }
        .padding(.leading, 15)
        .padding(.trailing, 9)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(MiniTimerBackground())
        .contentShape(Capsule())
        .modifier(WindowDrag())
        .onTapGesture(count: 2, perform: onOpenPanel)
        .contextMenu {
            Button("open timer", action: onOpenPanel)
            Button("hide floating timer", action: onHide)
        }
        .help("drag to move · double-click to open")
    }

    private var accent: Color {
        timer.mode == .rest ? TimerPanelView.breakGreen : TimerPanelView.focusRed
    }

    private var buttonSymbol: String {
        switch timer.state {
        case .idle, .paused: return "play.fill"
        case .running: return "pause.fill"
        case .ringing: return "checkmark"
        }
    }

    private var symbolColor: Color {
        timer.state == .idle || timer.state == .paused ? accent : .primary
    }

    private var buttonHelp: String {
        switch timer.state {
        case .idle: return "start"
        case .running: return "pause"
        case .paused: return "resume"
        case .ringing: return "dismiss"
        }
    }
}

/// Drags the window from anywhere on the pill. macOS 15+ has a SwiftUI gesture for
/// this; earlier systems fall back to DraggableHostingView's background dragging.
private struct WindowDrag: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.gesture(WindowDragGesture())
        } else {
            content
        }
    }
}

private struct MiniTimerBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(Glass.regular, in: Capsule())
        } else {
            Capsule()
                .fill(scheme == .dark ? Color(white: 0.06) : Color(white: 0.97))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        }
    }
}

// MARK: - Controller

@MainActor
final class MiniTimerController {
    private let timer: TimerModel
    private let prefs: Preferences
    private let openPanel: () -> Void
    private var window: NonKeyPanel?
    private var shouldBeVisible = false
    private var moveObserver: NSObjectProtocol?

    init(timer: TimerModel, prefs: Preferences, openPanel: @escaping () -> Void) {
        self.timer = timer
        self.prefs = prefs
        self.openPanel = openPanel
    }

    /// Shows or hides the floating timer according to the setting and timer state.
    func update() {
        let visible: Bool
        switch prefs.floatingTimer {
        case .off: visible = false
        case .always: visible = true
        case .active: visible = timer.state != .idle
        }
        visible ? show() : hide()
    }

    private func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        guard !shouldBeVisible || !window.isVisible else { return }
        shouldBeVisible = true
        if !window.isVisible {
            window.setFrameOrigin(validOrigin(for: window.frame.size))
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard shouldBeVisible, let window else { return }
        shouldBeVisible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Unless something asked to show it again meanwhile.
                if self?.shouldBeVisible == false { window.orderOut(nil) }
            }
        })
    }

    private func makeWindow() -> NonKeyPanel {
        let size = MiniTimerView.size
        let window = NonKeyPanel(contentRect: NSRect(origin: .zero, size: size))
        window.level = .statusBar
        window.isMovableByWindowBackground = true
        let view = MiniTimerView(
            timer: timer,
            onOpenPanel: { [weak self] in self?.openPanel() },
            onHide: { [weak self] in self?.prefs.floatingTimer = .off }
        )
        let hosting = DraggableHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = size.height / 2
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        window.contentView = hosting
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowMoved() }
        }
        return window
    }

    // MARK: Position

    /// Remembers where the floating timer was dragged to.
    private func windowMoved() {
        guard let window, shouldBeVisible else { return }
        prefs.floatingTimerOrigin = window.frame.origin
    }

    /// The saved spot (or top-right corner), pulled back on screen if displays changed.
    private func validOrigin(for size: CGSize, preferred: CGPoint? = nil) -> CGPoint {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        guard let fallback = fallbackScreen?.visibleFrame else { return preferred ?? .zero }
        let wanted = preferred ?? prefs.floatingTimerOrigin
            ?? CGPoint(x: fallback.maxX - size.width - 20, y: fallback.maxY - size.height - 16)
        let center = CGPoint(x: wanted.x + size.width / 2, y: wanted.y + size.height / 2)
        let frame = NSScreen.screens.first { $0.frame.contains(center) }?.visibleFrame ?? fallback
        return CGPoint(x: min(max(wanted.x, frame.minX + 4), frame.maxX - size.width - 4),
                       y: min(max(wanted.y, frame.minY + 4), frame.maxY - size.height - 4))
    }
}
