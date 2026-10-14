import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    let alarm: AlarmPlayer

    enum Tab: String, CaseIterable {
        case timer, sounds, automation, general
    }

    @StateObject private var tab = LocalState(Tab.timer)
    @StateObject private var shortcuts = LocalState<[String]?>(nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("section", selection: $tab.value) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.bottom, 2)

            switch tab.value {
            case .timer: timerTab
            case .sounds: soundsTab
            case .automation: automationTab
            case .general: generalTab
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 13.5))
        .padding(.horizontal, 20)
        .padding(.top, 38)
        .padding(.bottom, 20)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Tabs

    @ViewBuilder
    private var timerTab: some View {
        SettingsCard("lengths", systemImage: "timer") {
            Text("presets (min):")
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    MinuteField(value: clamped(\.presets[index]))
                }
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 10) {
                labeled("break") { MinuteField(value: clamped(\.breakMinutes)) }
                labeled("long break") { MinuteField(value: clamped(\.longBreakMinutes)) }
                labeled("every") {
                    MinuteField(value: Binding(
                        get: { prefs.longBreakEvery },
                        set: { prefs.longBreakEvery = min(max($0, 0), 12) }
                    ), range: 0...12, suffix: "×")
                }
            }
            Text(prefs.longBreakEvery > 0
                 ? "a long break follows every \(prefs.longBreakEvery) focus sessions"
                 : "long breaks are off")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        SettingsCard("goal", systemImage: "target") {
            HStack(spacing: 10) {
                Text("daily goal:")
                MinuteField(value: Binding(
                    get: { prefs.dailyGoal },
                    set: { prefs.dailyGoal = min(max($0, 0), 24) }
                ), range: 0...24)
                .frame(width: 84)
                Text(prefs.dailyGoal > 0 ? "sessions a day" : "off")
                    .foregroundStyle(.secondary)
            }
        }

        SettingsCard("flow", systemImage: "arrow.triangle.2.circlepath") {
            Toggle("start break automatically after focus", isOn: $prefs.autoStartBreak)
            Toggle("start focus automatically after a break", isOn: $prefs.autoStartFocus)
            Toggle("show timer when it finishes", isOn: $prefs.showPanelOnFinish)
            Toggle("pause when the screen locks", isOn: $prefs.pauseOnLock)
        }

        SettingsCard("breaks", systemImage: "cup.and.saucer") {
            HStack(spacing: 10) {
                Text("break screen:")
                Picker("break screen", selection: $prefs.breakScreen) {
                    Text("off").tag(Preferences.BreakScreen.off)
                    Text("reminder").tag(Preferences.BreakScreen.reminder)
                    Text("blocking").tag(Preferences.BreakScreen.blocking)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text(breakScreenHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var soundsTab: some View {
        SettingsCard("alarm", systemImage: "bell") {
            HStack(spacing: 10) {
                Text("sound:")
                Picker("sound", selection: $prefs.alarmSound) {
                    ForEach(AlarmPlayer.availableSounds, id: \.self) { name in
                        Text(name.lowercased()).tag(name)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: prefs.alarmSound) { sound in
                    alarm.preview(sound: sound, volume: max(prefs.volume, 0.2))
                }
            }
            volumeSlider(value: $prefs.volume) {
                alarm.preview(sound: prefs.alarmSound, volume: prefs.volume)
            }
            Toggle("automatically mute after 5 seconds", isOn: $prefs.autoMute)
        }

        SettingsCard("focus sound", systemImage: "waveform") {
            Picker("focus sound", selection: $prefs.focusSound) {
                Text("off").tag(Preferences.FocusSound.off)
                Text("white").tag(Preferences.FocusSound.white)
                Text("pink").tag(Preferences.FocusSound.pink)
                Text("brown").tag(Preferences.FocusSound.brown)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            volumeSlider(value: $prefs.focusSoundVolume)
                .disabled(prefs.focusSound == .off)
            Text("plays quietly while a focus session runs; brown is the deepest and softest")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var automationTab: some View {
        SettingsCard("shortcuts", systemImage: "square.2.layers.3d") {
            shortcutPicker("when focus starts:", selection: $prefs.shortcutOnFocusStart)
            shortcutPicker("when focus ends:", selection: $prefs.shortcutOnFocusEnd)
            Text("run any shortcut from the Shortcuts app — for example one that turns Do Not Disturb on, and another that turns it off. Pausing doesn't count as ending.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if shortcuts.value?.isEmpty == true {
                Text("no shortcuts found — create one in the Shortcuts app first")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .task {
            if shortcuts.value == nil { shortcuts.value = await ShortcutsRunner.list() }
        }
    }

    @ViewBuilder
    private var generalTab: some View {
        SettingsCard("menu bar", systemImage: "menubar.rectangle") {
            HStack(spacing: 10) {
                Text("icon:")
                Picker("menu bar icon", selection: $prefs.iconStyle) {
                    Text("compact").tag(Preferences.IconStyle.compact)
                    Text("expanded").tag(Preferences.IconStyle.expanded)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }
            Toggle("increase contrast", isOn: $prefs.increaseContrast)
        }

        SettingsCard("floating timer", systemImage: "pip") {
            Picker("floating timer", selection: $prefs.floatingTimer) {
                Text("off").tag(Preferences.FloatingTimer.off)
                Text("while a timer runs").tag(Preferences.FloatingTimer.active)
                Text("always").tag(Preferences.FloatingTimer.always)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("a small glass timer that stays on top, even over full-screen apps. drag it anywhere; double-click to open the full timer.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        SettingsCard("app", systemImage: "gearshape") {
            Toggle("open with ⌥⌘P from anywhere", isOn: $prefs.globalShortcut)
            Toggle("launch at login", isOn: Binding(
                get: { prefs.launchAtLogin },
                set: { prefs.setLaunchAtLogin($0) }
            ))
        }

        Text("Focal \(Self.version) · made by Dhruv")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private var breakScreenHint: String {
        switch prefs.breakScreen {
        case .off: return "breaks only show in the menu bar and the timer panel"
        case .reminder: return "your screens dim during breaks with a countdown; you can keep clicking through"
        case .blocking: return "your screens are covered until the break ends, with a button to skip it"
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Pieces

    private func volumeSlider(value: Binding<Double>, onRelease: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: value, in: 0...1) { editing in
                if !editing { onRelease?() }
            }
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
        }
    }

    private func shortcutPicker(_ title: String, selection: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 118, alignment: .leading)
            Picker(title, selection: selection) {
                Text("none").tag("")
                let names = shortcuts.value ?? []
                // Keep a saved choice visible even if it's not in the (loading or changed) list.
                if !selection.wrappedValue.isEmpty && !names.contains(selection.wrappedValue) {
                    Text(selection.wrappedValue).tag(selection.wrappedValue)
                }
                ForEach(names, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
    }

    private func clamped(_ keyPath: ReferenceWritableKeyPath<Preferences, Int>) -> Binding<Int> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { prefs[keyPath: keyPath] = min(max($0, 1), Preferences.maxMinutes) }
        )
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
    }
}

/// Number field with a stepper, styled like the preset boxes.
private struct MinuteField: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...Preferences.maxMinutes
    var suffix: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 15))
                .monospacedDigit()
            if let suffix {
                Text(suffix).foregroundStyle(.secondary)
            }
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }
}
