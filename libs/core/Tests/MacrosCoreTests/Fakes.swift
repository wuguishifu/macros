import Foundation

@testable import MacrosCore

let ms: UInt64 = 1_000_000

/// A clock that only advances when slept on (or advanced manually).
final class FakeTime: TimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: UInt64
    /// Called on every sleep, after time advances — lets tests act "during" playback.
    var onSleep: (@Sendable (UInt64) -> Void)?

    init(start: UInt64 = 1_000 * ms) { current = start }

    func now() -> UInt64 { lock.withLock { current } }

    func sleep(until deadline: UInt64) {
        let now = lock.withLock {
            current = max(current, deadline)
            return current
        }
        onSleep?(now)
    }
}

/// Records every posted event along with the fake time it was posted.
final class CapturingSink: EventSink, @unchecked Sendable {
    private let lock = NSLock()
    private let time: TimeSource
    private var posted: [(time: UInt64, event: MacroEvent)] = []

    init(time: TimeSource) { self.time = time }

    func post(_ event: MacroEvent) {
        let now = time.now()
        lock.withLock { posted.append((now, event)) }
    }

    var events: [MacroEvent] { lock.withLock { posted.map(\.event) } }
    var times: [UInt64] { lock.withLock { posted.map(\.time) } }
}

/// A runner that doesn't play anything; tests drive progress/completion by hand.
final class FakeRunner: PlaybackRunner, @unchecked Sendable {
    struct Invocation {
        var macro: Macro
        var count: Int
        var settings: PlaybackSettings
        var cancel: CancellationFlag
        var progress: @Sendable (Int) -> Void
        var completion: @Sendable (PlaybackOutcome) -> Void
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    var invocations: [Invocation] { lock.withLock { _invocations } }

    func start(
        macro: Macro, count: Int, settings: PlaybackSettings, cancel: CancellationFlag,
        progress: @escaping @Sendable (Int) -> Void, completion: @escaping @Sendable (PlaybackOutcome) -> Void
    ) {
        lock.withLock {
            _invocations.append(
                Invocation(
                    macro: macro, count: count, settings: settings, cancel: cancel, progress: progress,
                    completion: completion))
        }
    }
}

final class Collector<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []
    var values: [T] { lock.withLock { _values } }
    func append(_ value: T) { lock.withLock { _values.append(value) } }
}

// MARK: - Event helpers

let ctrl = Modifiers.control.rawValue
let cmd = Modifiers.command.rawValue
let shift = Modifiers.shift.rawValue

/// ANSI key codes used in tests.
enum Key {
    static let a: UInt16 = 0
    static let b: UInt16 = 11
    static let x: UInt16 = 7
    static let tab: UInt16 = 48
    static let one: UInt16 = 18
    static let two: UInt16 = 19
    static let leftCmd: UInt16 = 55
    static let leftCtrl: UInt16 = 59
    static let leftShift: UInt16 = 56
}

func flagsEvent(_ keyCode: UInt16, _ flags: UInt64) -> MacroEvent {
    MacroEvent(kind: .flagsChanged, flags: flags, keyCode: keyCode)
}
