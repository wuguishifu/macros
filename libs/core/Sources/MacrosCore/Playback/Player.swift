/// Replays a macro against a `TimeSource` and `EventSink`. `run` blocks the calling thread until done.
public final class Player: Sendable {
    private let sink: EventSink
    private let time: TimeSource
    /// Longest single sleep, so cancellation is noticed quickly.
    private let pollIntervalNs: UInt64

    public init(sink: EventSink, time: TimeSource, pollIntervalNs: UInt64 = 10_000_000) {
        self.sink = sink
        self.time = time
        self.pollIntervalNs = pollIntervalNs
    }

    public func run(
        macro: Macro,
        count: Int,
        settings: PlaybackSettings,
        cancel: CancellationFlag,
        progress: (Int) -> Void = { _ in }
    ) -> PlaybackOutcome {
        let schedule = PlaybackSchedule(macro: macro, settings: settings)
        let gapNs = UInt64(max(0, settings.interIterationGapMs)) * 1_000_000
        let total = max(1, count)
        var held = HeldInputState()
        var iterationStart = time.now()

        defer {
            for event in held.releaseEvents() { sink.post(event) }
        }

        for iteration in 1...total {
            progress(iteration)
            for entry in schedule.entries {
                guard wait(until: iterationStart + entry.offsetNs, cancel: cancel) else { return .aborted }
                sink.post(entry.event)
                held.apply(entry.event)
            }
            if iteration < total {
                iterationStart += schedule.durationNs + gapNs
                guard wait(until: iterationStart, cancel: cancel) else { return .aborted }
            }
        }
        return cancel.isCancelled ? .aborted : .completed
    }

    /// Sleeps until `deadline` in short slices. Returns `false` if cancelled first.
    private func wait(until deadline: UInt64, cancel: CancellationFlag) -> Bool {
        while true {
            if cancel.isCancelled { return false }
            let now = time.now()
            if now >= deadline { return true }
            time.sleep(until: min(deadline, now + pollIntervalNs))
        }
    }
}

/// Tracks keys, modifiers and buttons a macro has pressed but not released, so they can be released afterwards.
struct HeldInputState {
    private(set) var keys: [UInt16] = []
    private(set) var modifierKeys: [UInt16] = []
    private(set) var buttons: Set<Int> = []
    private var location: (x: Double, y: Double)?
    private var flags: UInt64 = 0

    mutating func apply(_ event: MacroEvent) {
        flags = event.flags
        if let x = event.x, let y = event.y { location = (x, y) }
        switch event.kind {
        case .keyDown:
            if let code = event.keyCode, !keys.contains(code) { keys.append(code) }
        case .keyUp:
            keys.removeAll { $0 == event.keyCode }
        case .flagsChanged:
            guard let code = event.keyCode, let mask = KeyCodes.modifierFlag(forKeyCode: code) else { break }
            if event.flags & mask != 0 {
                if !modifierKeys.contains(code) { modifierKeys.append(code) }
            } else {
                modifierKeys.removeAll { $0 == code }
            }
        case .mouseDown:
            buttons.insert(event.button ?? 0)
        case .mouseUp:
            buttons.remove(event.button ?? 0)
        case .mouseMove, .mouseDrag, .scroll:
            break
        }
    }

    func releaseEvents() -> [MacroEvent] {
        var events: [MacroEvent] = []
        var flags = self.flags
        for code in keys {
            events.append(.key(.keyUp, code, flags: flags))
        }
        if let location {
            for button in buttons.sorted() {
                events.append(.mouse(.mouseUp, x: location.x, y: location.y, button: button, flags: flags))
            }
        }
        for code in modifierKeys.reversed() {
            // Clear this modifier's bit plus the device-dependent low bits.
            flags &= ~(KeyCodes.modifierFlag(forKeyCode: code) ?? 0) & ~0xFFFF
            events.append(MacroEvent(kind: .flagsChanged, flags: flags, keyCode: code))
        }
        return events
    }
}
