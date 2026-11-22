import CoreGraphics
import Foundation
import MacrosCore
import os

private let logger = Logger(subsystem: "dev.wuguishifu.macros", category: "tap")

/// Hosts the active session event tap on a dedicated thread and routes every event through the engine.
final class EventTap: @unchecked Sendable {
    private static let eventTypes: [CGEventType] = [
        .keyDown, .keyUp, .flagsChanged,
        .mouseMoved, .scrollWheel,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]

    private let engine: MacroEngine
    private let translator: KeyTranslator
    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    init(engine: MacroEngine, translator: KeyTranslator) {
        self.engine = engine
        self.translator = translator
    }

    var isRunning: Bool { lock.withLock { port != nil } }

    /// Installs the tap. Returns `false` if macOS refused (usually: no Accessibility permission).
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask = Self.eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    return Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            logger.error("CGEvent.tapCreate failed")
            return false
        }

        lock.withLock {
            self.port = port
            self.source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        }

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in runLoopBody(ready: ready) }
        thread.name = "dev.wuguishifu.macros.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        logger.notice("Event tap started")
        return true
    }

    func stop() {
        let (port, runLoop) = lock.withLock {
            defer {
                self.port = nil
                self.source = nil
                self.runLoop = nil
            }
            return (self.port, self.runLoop)
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func runLoopBody(ready: DispatchSemaphore) {
        let (port, source) = lock.withLock {
            runLoop = CFRunLoopGetCurrent()
            return (self.port, self.source)
        }
        if let port, let source {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
        }
        ready.signal()
        CFRunLoopRun()
        logger.notice("Event tap thread exiting")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("Event tap was disabled (\(type.rawValue)); re-enabling")
            if let port = lock.withLock({ port }) { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let macroEvent = MacroEvent(event, type: type) else { return Unmanaged.passUnretained(event) }

        let character = macroEvent.kind == .keyDown ? macroEvent.keyCode.flatMap(translator.character(for:)) : nil
        let input = InputEvent(
            event: macroEvent,
            timestamp: DispatchTime.now().uptimeNanoseconds,
            character: character,
            isSynthetic: event.isMacrosSynthetic)

        switch engine.handle(input) {
        case .pass: return Unmanaged.passUnretained(event)
        case .swallow: return nil
        }
    }
}
