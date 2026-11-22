/// Global playback settings.
public struct PlaybackSettings: Codable, Hashable, Sendable {
    /// Playback speed multiplier (1, 2, 4…).
    public var speed: Double
    /// Any single gap longer than this is shortened to it. `nil` = no cap.
    public var idleCapMs: Int?
    /// Extra wait between repeats. Not affected by `speed`.
    public var interIterationGapMs: Int

    public init(speed: Double = 1, idleCapMs: Int? = nil, interIterationGapMs: Int = 0) {
        self.speed = speed
        self.idleCapMs = idleCapMs
        self.interIterationGapMs = interIterationGapMs
    }
}

/// The timing of one iteration of a macro after applying speed and idle cap.
public struct PlaybackSchedule: Sendable {
    public struct Entry: Hashable, Sendable {
        /// Nanoseconds after the iteration starts.
        public var offsetNs: UInt64
        public var event: MacroEvent
    }

    public let entries: [Entry]
    /// Length of one iteration, including the trailing gap.
    public let durationNs: UInt64

    public init(macro: Macro, settings: PlaybackSettings) {
        let speed = settings.speed > 0 ? settings.speed : 1
        let cap = settings.idleCapMs.map { Double(max(0, $0)) }

        func scaled(_ deltaMs: Int) -> Double {
            var delta = Double(max(0, deltaMs))
            if let cap { delta = min(delta, cap) }
            return delta / speed
        }

        var elapsedMs = 0.0
        var previous = macro.events.first?.t ?? 0
        entries = macro.events.map { event in
            elapsedMs += scaled(event.t - previous)
            previous = event.t
            return Entry(offsetNs: UInt64(elapsedMs * 1_000_000), event: event)
        }
        elapsedMs += scaled(macro.trailingGapMs)
        durationNs = UInt64(elapsedMs * 1_000_000)
    }
}
