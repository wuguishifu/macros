import AppKit
import MacrosCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let translator: KeyTranslator
    /// Called with `true` while a shortcut recorder is capturing, so the engine stops intercepting keys.
    let onCaptureChange: (Bool) -> Void

    var body: some View {
        Form {
            Section("Shortcuts") {
                ShortcutRecorder(
                    title: "Record / stop", combo: $settings.recordLeader, translator: translator,
                    onCaptureChange: onCaptureChange,
                    validate: { $0 == settings.playLeader ? "Already used for Play" : nil })
                ShortcutRecorder(
                    title: "Play", combo: $settings.playLeader, translator: translator,
                    onCaptureChange: onCaptureChange,
                    validate: { $0 == settings.recordLeader ? "Already used for Record" : nil })
                Picker("Chord timeout", selection: $settings.chordTimeoutSeconds) {
                    ForEach(AppSettings.chordTimeoutOptions, id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
            }

            Section("Playback") {
                Picker("Speed", selection: $settings.speed) {
                    ForEach(AppSettings.speedOptions, id: \.self) { Text("\(Int($0))×").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Cap idle gaps at", selection: $settings.idleCapSeconds) {
                    ForEach(AppSettings.idleCapOptions, id: \.self) { Text($0 == 0 ? "Off" : "\($0) s").tag($0) }
                }
                LabeledContent("Gap between repeats") {
                    HStack(spacing: 6) {
                        TextField("", value: $settings.interIterationGapMs, format: .number)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Text("ms")
                        Stepper("", value: $settings.interIterationGapMs, in: 0...60_000, step: 100)
                            .labelsHidden()
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.shortVersion)
                Link("github.com/wuguishifu/macros", destination: URL(string: "https://github.com/wuguishifu/macros")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Click, then type a shortcut. Esc cancels. Requires at least one of ⌘⌃⌥.
struct ShortcutRecorder: View {
    let title: String
    @Binding var combo: KeyCombo
    let translator: KeyTranslator
    let onCaptureChange: (Bool) -> Void
    let validate: (KeyCombo) -> String?

    @State private var capturing = false
    @State private var monitor: Any?
    @State private var error: String?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Button(capturing ? "Type shortcut…" : translator.display(combo)) {
                    capturing ? stop() : begin()
                }
                .monospaced()
                .frame(minWidth: 110)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .onDisappear { stop() }
    }

    private func begin() {
        error = nil
        capturing = true
        onCaptureChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == KeyCodes.escape {
                stop()
                return nil
            }
            let candidate = KeyCombo(
                keyCode: event.keyCode, modifiers: Modifiers(flags: UInt64(event.modifierFlags.rawValue)))
            guard candidate.isValidLeader else {
                error = "Include ⌘, ⌃ or ⌥"
                return nil
            }
            if let problem = validate(candidate) {
                error = problem
                return nil
            }
            combo = candidate
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if capturing {
            capturing = false
            onCaptureChange(false)
        }
    }
}

extension Bundle {
    var shortVersion: String {
        let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
