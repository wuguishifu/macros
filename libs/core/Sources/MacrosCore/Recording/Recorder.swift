/// Accumulates events for one recording and applies the leading/trailing clean-up rules.
///
/// A reference type so the engine can append to it in place on every event without copying the buffer.
public final class Recorder {
    private var entries: [(timestamp: UInt64, event: MacroEvent)] = []
    private var heldAtStart: Modifiers
    private var inLeadingRelease = true

    /// - Parameter startModifiers: modifiers still held when recording began (left over from the start chord).
    public init(startModifiers: Modifiers) {
        heldAtStart = startModifiers
    }

    public var count: Int { entries.count }

    public func record(_ event: MacroEvent, at timestamp: UInt64) {
        if inLeadingRelease {
            switch event.kind {
            case .flagsChanged where event.modifiers.isSubset(of: heldAtStart):
                // Releasing modifiers left over from the start chord: drop it.
                heldAtStart = event.modifiers
                return
            case .mouseMove:
                break
            default:
                inLeadingRelease = false
            }
        }
        entries.append((timestamp, event))
    }

    public struct Result: Equatable, Sendable {
        public var events: [MacroEvent]
        public var trailingGapMs: Int
    }

    /// Finishes the recording.
    ///
    /// Drops the presses of the stop leader's modifiers at the very end (and anything after the first of them),
    /// rebases timestamps so the first event is at t = 0 (dropping the leading gap) and measures the trailing gap.
    /// - Returns: `nil` if nothing remains.
    public func finish(stopAt: UInt64, leaderModifiers: Modifiers) -> Result? {
        var cutoff = entries.count
        var index = entries.count - 1
        while index >= 0 {
            let event = entries[index].event
            if event.kind == .mouseMove {
                index -= 1
                continue
            }
            if event.kind == .flagsChanged, !event.modifiers.isEmpty, event.modifiers.isSubset(of: leaderModifiers) {
                cutoff = index
                index -= 1
                continue
            }
            break
        }

        let kept = entries[..<cutoff]
        guard let first = kept.first, let last = kept.last else { return nil }
        let cutoffTimestamp = cutoff < entries.count ? entries[cutoff].timestamp : stopAt

        let events = kept.map { entry in
            var event = entry.event
            event.t = Self.milliseconds(from: first.timestamp, to: entry.timestamp)
            return event
        }
        return Result(events: events, trailingGapMs: Self.milliseconds(from: last.timestamp, to: cutoffTimestamp))
    }

    private static func milliseconds(from start: UInt64, to end: UInt64) -> Int {
        end > start ? Int((end - start) / 1_000_000) : 0
    }
}
