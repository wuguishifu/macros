import AppKit
import MacrosCore
import SwiftUI
import os

private let logger = Logger(subsystem: "dev.wuguishifu.macros", category: "app")

/// Owns the engine, tap and windows, and keeps `AppModel` in sync.
@MainActor
final class AppController {
    let model: AppModel
    let settings: AppSettings
    let translator: KeyTranslator
    private let bank: RegisterBank
    private let engine: MacroEngine
    private let tap: EventTap
    private let windows = WindowPresenter()
    private var hud: HUDController?
    private var timers: [Timer] = []

    init() {
        let model = AppModel()
        let settings = AppSettings()
        let bank = RegisterBank(store: RegisterStore(directory: RegisterStore.defaultDirectory))
        let runner = ThreadPlaybackRunner(player: Player(sink: CGEventSink(), time: SystemTimeSource()))
        let engine = MacroEngine(
            bank: bank,
            runner: runner,
            config: settings.engineConfig,
            onStatus: { status in
                DispatchQueue.main.async { MainActor.assumeIsolated { model.status = status } }
            },
            onNotice: { text in
                DispatchQueue.main.async { MainActor.assumeIsolated { model.showNotice(text) } }
            })
        let translator = KeyTranslator()

        self.model = model
        self.settings = settings
        self.bank = bank
        self.engine = engine
        self.translator = translator
        self.tap = EventTap(engine: engine, translator: translator)
    }

    func start() {
        hud = HUDController(model: model, translator: translator, settings: settings)
        model.onHUDChange = { [weak self] in self?.hud?.update() }

        bank.onChange { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reloadRegisters() } }
        }
        reloadRegisters()

        settings.onChange = { [weak self] in
            guard let self else { return }
            engine.setConfig(settings.engineConfig)
        }

        schedule(every: 0.2) { [weak self] in self?.engine.tick(now: DispatchTime.now().uptimeNanoseconds) }
        schedule(every: 1.0) { [weak self] in self?.checkPermission() }
        schedule(every: 0.5) { [weak self] in self?.checkSecureInput() }

        checkPermission(initial: true)
    }

    func shutdown() {
        engine.reset()
        tap.stop()
    }

    // MARK: - Actions

    func play(_ register: Register) {
        // Give the menu time to close so playback doesn't race its dismissal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [engine] in engine.play(register) }
    }

    func rename(_ register: Register) {
        let current = bank.macro(for: register)?.label ?? ""
        DispatchQueue.main.async { [bank] in
            let alert = NSAlert()
            alert.messageText = "Label for @\(register)"
            alert.informativeText = "Shown next to the register in the menu. Leave empty to remove."
            let field = NSTextField(string: current)
            field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let label = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            bank.setLabel(label.isEmpty ? nil : label, for: register)
        }
    }

    func clear(_ register: Register) {
        DispatchQueue.main.async { [bank] in
            let alert = NSAlert()
            alert.messageText = "Clear @\(register)?"
            alert.informativeText = "The recorded macro will be deleted."
            alert.addButton(withTitle: "Clear")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { bank.remove(register) }
        }
    }

    func showSettings() {
        windows.show(id: "settings", title: "Macros Settings") {
            SettingsView(settings: self.settings, translator: self.translator) { [weak self] capturing in
                self?.engine.setSuspended(capturing)
            }
        }
    }

    func showPermissions() {
        windows.show(id: "permissions", title: "Macros Permissions") {
            PermissionsView(model: self.model)
        }
    }

    // MARK: - Polling

    private func reloadRegisters() {
        model.registers = bank.all
    }

    private func checkPermission(initial: Bool = false) {
        let granted = Permissions.isAccessibilityGranted
        guard initial || granted != model.accessibilityGranted else { return }
        model.accessibilityGranted = granted

        if granted {
            logger.notice("Accessibility granted")
            windows.close(id: "permissions")
            engine.setSuspended(false)
            model.tapFailed = !tap.start()
        } else {
            logger.notice("Accessibility not granted")
            engine.setSuspended(true)
            tap.stop()
            if initial { showPermissions() }
        }
    }

    private func checkSecureInput() {
        let active = model.isRecording && Permissions.isSecureInputActive
        if active != model.secureInputActive { model.secureInputActive = active }
    }

    private func schedule(every interval: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }
}
