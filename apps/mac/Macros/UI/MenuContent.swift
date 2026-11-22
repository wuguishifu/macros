import AppKit
import MacrosCore
import SwiftUI

struct MenuBarIcon: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.menuBarSymbol)
    }
}

struct MenuContent: View {
    let controller: AppController
    private var model: AppModel { controller.model }
    private var settings: AppSettings { controller.settings }

    var body: some View {
        Text(statusLine)

        Divider()

        if model.registers.isEmpty {
            Text("No macros yet")
            Text("\(controller.translator.display(settings.recordLeader)) then a–z to record")
        } else {
            ForEach(model.registers, id: \.register) { macro in
                Menu(title(for: macro)) {
                    Button("Play") { controller.play(macro.register) }
                    Button("Rename…") { controller.rename(macro.register) }
                    Divider()
                    Button("Clear…") { controller.clear(macro.register) }
                    Divider()
                    Text("Recorded \(macro.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }

        Divider()

        if !model.accessibilityGranted {
            Button("Grant Accessibility Access…") { controller.showPermissions() }
        }
        Button("Settings…") { controller.showSettings() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Macros") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if !model.accessibilityGranted { return "Needs Accessibility access" }
        if model.tapFailed { return "Couldn't start input capture" }
        let record = controller.translator.display(settings.recordLeader)
        let play = controller.translator.display(settings.playLeader)
        return switch model.status {
        case .idle, .suspended: "Record \(record) · Play \(play)"
        case .pendingRecord: "Waiting for register…"
        case .recording(let register, _): "Recording @\(register)"
        case .pendingPlay: "Waiting for register…"
        case .playing(let register, let iteration, let total): "Playing @\(register) (\(iteration)/\(total))"
        }
    }

    private func title(for macro: Macro) -> String {
        let seconds = Double(macro.durationMs) / 1000
        let duration = seconds.formatted(.number.precision(.fractionLength(1))) + "s"
        let label = macro.label.map { "  \($0)" } ?? ""
        return "@\(macro.register)\(label) — \(duration) · \(macro.events.count) events"
    }
}
