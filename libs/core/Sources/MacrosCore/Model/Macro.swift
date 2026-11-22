import Foundation

/// The contents of one register.
public struct Macro: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var register: Register
    public var label: String?
    public var recordedAt: Date
    /// Wait after the last event (time between it and the stop chord).
    public var trailingGapMs: Int
    public var events: [MacroEvent]

    public init(
        register: Register,
        label: String? = nil,
        recordedAt: Date = Date(),
        trailingGapMs: Int,
        events: [MacroEvent]
    ) {
        self.schemaVersion = Macro.currentSchemaVersion
        self.register = register
        self.label = label
        self.recordedAt = recordedAt
        self.trailingGapMs = trailingGapMs
        self.events = events
    }

    public var durationMs: Int { (events.last?.t ?? 0) + trailingGapMs }

    /// Appends a newly recorded take after this macro's end (including its trailing gap).
    public func appending(_ newEvents: [MacroEvent], trailingGapMs newTrailingGap: Int, recordedAt: Date = Date())
        -> Macro
    {
        let offset = durationMs
        var copy = self
        copy.events += newEvents.map { event in
            var shifted = event
            shifted.t += offset
            return shifted
        }
        copy.trailingGapMs = newTrailingGap
        copy.recordedAt = recordedAt
        return copy
    }
}
