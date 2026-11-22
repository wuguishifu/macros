import Foundation

/// An input event as seen by the event tap.
public struct InputEvent: Sendable {
    /// The event payload (`t` is unused here; timing comes from `timestamp`).
    public var event: MacroEvent
    /// Monotonic nanoseconds when the event was observed.
    public var timestamp: UInt64
    /// For key-downs: the key's character on the current layout, ignoring modifiers (lowercase).
    public var character: Character?
    /// True for events Macros itself posted.
    public var isSynthetic: Bool

    public init(event: MacroEvent, timestamp: UInt64, character: Character? = nil, isSynthetic: Bool = false) {
        self.event = event
        self.timestamp = timestamp
        self.character = character
        self.isSynthetic = isSynthetic
    }
}

public enum TapDecision: Sendable, Equatable {
    case pass
    case swallow
}

public enum EngineStatus: Equatable, Sendable {
    case idle
    /// Engine is ignoring input (no permission, or a shortcut recorder is capturing).
    case suspended
    case pendingRecord
    case recording(Register, appending: Bool)
    case pendingPlay(count: String)
    case playing(Register, iteration: Int, total: Int)
}

public struct EngineConfig: Equatable, Sendable {
    public static let maxCountDigits = 3

    public var recordLeader: KeyCombo
    public var playLeader: KeyCombo
    public var chordTimeoutMs: Int
    public var playback: PlaybackSettings

    public init(
        recordLeader: KeyCombo = .defaultRecord,
        playLeader: KeyCombo = .defaultPlay,
        chordTimeoutMs: Int = 3000,
        playback: PlaybackSettings = PlaybackSettings()
    ) {
        self.recordLeader = recordLeader
        self.playLeader = playLeader
        self.chordTimeoutMs = chordTimeoutMs
        self.playback = playback
    }
}

/// The chord/record/play state machine. Every physical input event goes through `handle(_:)`, which decides whether
/// the event reaches the frontmost app.
///
/// Thread-safe: state is guarded by a lock; callbacks and side effects run after the lock is released.
public final class MacroEngine: @unchecked Sendable {
    private enum State {
        case idle
        case pendingRecord(since: UInt64)
        case recording(Register, appending: Bool, Recorder)
        case pendingPlay(digits: String, since: UInt64)
        case playing(Register, CancellationFlag, iteration: Int, total: Int)
    }

    private enum Effect {
        case status(EngineStatus)
        case notice(String)
        case startPlayback(Macro, count: Int, PlaybackSettings, CancellationFlag)
    }

    private let lock = NSLock()
    private let bank: RegisterBank
    private let runner: PlaybackRunner
    private let onStatus: @Sendable (EngineStatus) -> Void
    private let onNotice: @Sendable (String) -> Void

    private var config: EngineConfig
    private var state: State = .idle
    private var suspended = false
    /// Keys whose key-down we swallowed; their auto-repeats and key-up are swallowed too.
    private var swallowedKeys: Set<UInt16> = []
    private var lastPlayed: Register?
    private var lastStatus: EngineStatus = .idle
    private var effects: [Effect] = []

    public init(
        bank: RegisterBank,
        runner: PlaybackRunner,
        config: EngineConfig = EngineConfig(),
        onStatus: @escaping @Sendable (EngineStatus) -> Void = { _ in },
        onNotice: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.bank = bank
        self.runner = runner
        self.config = config
        self.onStatus = onStatus
        self.onNotice = onNotice
    }

    // MARK: - Public API

    public var status: EngineStatus { lock.withLock { currentStatus } }

    public func handle(_ input: InputEvent) -> TapDecision {
        mutate { decide(input) }
    }

    /// Expires pending chords. Call periodically with the same clock the tap timestamps use.
    public func tick(now: UInt64) {
        mutate {
            switch state {
            case .pendingRecord(let since), .pendingPlay(_, let since):
                if now >= since + UInt64(max(0, config.chordTimeoutMs)) * 1_000_000 {
                    state = .idle
                }
            default:
                break
            }
        }
    }

    /// Plays a register (e.g. from the menu). Ignored unless idle.
    public func play(_ register: Register, count: Int = 1) {
        mutate {
            guard case .idle = state, !suspended else { return }
            startPlayback(register, count: count)
        }
    }

    public func setConfig(_ newConfig: EngineConfig) {
        mutate { config = newConfig }
    }

    /// While suspended every event passes through untouched. Suspending aborts whatever is in progress.
    public func setSuspended(_ value: Bool) {
        mutate {
            if value { abortAll() }
            suspended = value
        }
    }

    /// Aborts playback and discards any recording in progress.
    public func reset() {
        mutate { abortAll() }
    }

    // MARK: - Decisions

    private func decide(_ input: InputEvent) -> TapDecision {
        if suspended || input.isSynthetic { return .pass }
        let event = input.event

        if let code = event.keyCode, swallowedKeys.contains(code) {
            if event.kind == .keyUp {
                swallowedKeys.remove(code)
                return .swallow
            }
            if event.kind == .keyDown { return .swallow }
        }

        switch state {
        case .idle:
            return decideIdle(input)
        case .pendingRecord:
            return decidePendingRecord(input)
        case .recording(let register, let appending, let recorder):
            return decideRecording(input, register: register, appending: appending, recorder: recorder)
        case .pendingPlay(let digits, _):
            return decidePendingPlay(input, digits: digits)
        case .playing(_, let cancel, _, _):
            return decidePlaying(input, cancel: cancel)
        }
    }

    private func decideIdle(_ input: InputEvent) -> TapDecision {
        let event = input.event
        guard event.kind == .keyDown, let code = event.keyCode else { return .pass }
        if config.recordLeader.matches(event) {
            swallowedKeys.insert(code)
            state = .pendingRecord(since: input.timestamp)
            return .swallow
        }
        if config.playLeader.matches(event) {
            swallowedKeys.insert(code)
            state = .pendingPlay(digits: "", since: input.timestamp)
            return .swallow
        }
        return .pass
    }

    private func decidePendingRecord(_ input: InputEvent) -> TapDecision {
        let event = input.event
        guard event.kind == .keyDown, let code = event.keyCode else { return .pass }
        swallowedKeys.insert(code)

        if code == KeyCodes.escape || config.recordLeader.matches(event) {
            state = .idle
            return .swallow
        }
        if let character = input.character, let register = Register(character) {
            let appending = event.modifiers.contains(.shift)
            state = .recording(register, appending: appending, Recorder(startModifiers: event.modifiers))
            return .swallow
        }
        state = .idle
        effects.append(.notice("Not a register — recording cancelled"))
        return .swallow
    }

    private func decideRecording(_ input: InputEvent, register: Register, appending: Bool, recorder: Recorder)
        -> TapDecision
    {
        let event = input.event
        if config.recordLeader.matches(event), let code = event.keyCode {
            swallowedKeys.insert(code)
            finishRecording(register, appending: appending, recorder: recorder, at: input.timestamp)
            return .swallow
        }
        if config.playLeader.matches(event), let code = event.keyCode {
            swallowedKeys.insert(code)
            effects.append(.notice("Can't play while recording"))
            return .swallow
        }
        recorder.record(event, at: input.timestamp)
        return .pass
    }

    private func decidePendingPlay(_ input: InputEvent, digits: String) -> TapDecision {
        let event = input.event
        guard event.kind == .keyDown, let code = event.keyCode else { return .pass }
        swallowedKeys.insert(code)

        if code == KeyCodes.escape {
            state = .idle
            return .swallow
        }
        let count = max(1, Int(digits) ?? 1)
        if config.playLeader.matches(event) {
            if let lastPlayed {
                startPlayback(lastPlayed, count: count)
            } else {
                state = .idle
                effects.append(.notice("Nothing played yet"))
            }
            return .swallow
        }
        if let character = input.character {
            if character.isASCII, character.isNumber, !event.modifiers.contains(.shift) {
                var digits = digits
                if digits.count < EngineConfig.maxCountDigits { digits.append(character) }
                state = .pendingPlay(digits: digits, since: input.timestamp)
                return .swallow
            }
            if let register = Register(character) {
                startPlayback(register, count: count)
                return .swallow
            }
        }
        state = .idle
        effects.append(.notice("Playback cancelled"))
        return .swallow
    }

    private func decidePlaying(_ input: InputEvent, cancel: CancellationFlag) -> TapDecision {
        let event = input.event
        if event.kind == .keyDown, let code = event.keyCode,
            code == KeyCodes.escape || config.playLeader.matches(event)
        {
            swallowedKeys.insert(code)
            cancel.cancel()
        }
        // All other physical input is blocked during playback.
        return .swallow
    }

    // MARK: - Transitions

    private func finishRecording(_ register: Register, appending: Bool, recorder: Recorder, at timestamp: UInt64) {
        state = .idle
        guard let result = recorder.finish(stopAt: timestamp, leaderModifiers: config.recordLeader.modifiers) else {
            effects.append(.notice("Empty recording — @\(register) unchanged"))
            return
        }
        let macro: Macro
        if appending, let existing = bank.macro(for: register) {
            macro = existing.appending(result.events, trailingGapMs: result.trailingGapMs)
        } else {
            macro = Macro(register: register, trailingGapMs: result.trailingGapMs, events: result.events)
        }
        bank.set(macro)
        effects.append(.notice(appending ? "Appended to @\(register)" : "Recorded @\(register)"))
    }

    private func startPlayback(_ register: Register, count: Int) {
        guard let macro = bank.macro(for: register), !macro.events.isEmpty else {
            state = .idle
            effects.append(.notice("@\(register) is empty"))
            return
        }
        lastPlayed = register
        let total = max(1, count)
        let cancel = CancellationFlag()
        state = .playing(register, cancel, iteration: 1, total: total)
        effects.append(.startPlayback(macro, count: total, config.playback, cancel))
    }

    private func playbackProgressed(_ iteration: Int, _ flag: CancellationFlag) {
        mutate {
            guard case .playing(let register, let cancel, _, let total) = state, cancel === flag else { return }
            state = .playing(register, cancel, iteration: iteration, total: total)
        }
    }

    private func playbackFinished(_ outcome: PlaybackOutcome, _ flag: CancellationFlag) {
        mutate {
            guard case .playing(_, let cancel, _, _) = state, cancel === flag else { return }
            state = .idle
            if outcome == .aborted { effects.append(.notice("Playback stopped")) }
        }
    }

    private func abortAll() {
        if case .playing(_, let cancel, _, _) = state { cancel.cancel() }
        state = .idle
        swallowedKeys.removeAll()
    }

    // MARK: - Plumbing

    private var currentStatus: EngineStatus {
        if suspended { return .suspended }
        switch state {
        case .idle: return .idle
        case .pendingRecord: return .pendingRecord
        case .recording(let register, let appending, _): return .recording(register, appending: appending)
        case .pendingPlay(let digits, _): return .pendingPlay(count: digits)
        case .playing(let register, _, let iteration, let total):
            return .playing(register, iteration: iteration, total: total)
        }
    }

    /// Runs `body` under the lock, then emits a status change if any, then performs queued effects.
    private func mutate<T>(_ body: () -> T) -> T {
        lock.lock()
        let result = body()
        let status = currentStatus
        if status != lastStatus {
            lastStatus = status
            effects.insert(.status(status), at: 0)
        }
        let pending = effects
        effects.removeAll()
        lock.unlock()

        for effect in pending { perform(effect) }
        return result
    }

    private func perform(_ effect: Effect) {
        switch effect {
        case .status(let status):
            onStatus(status)
        case .notice(let text):
            onNotice(text)
        case .startPlayback(let macro, let count, let settings, let cancel):
            runner.start(
                macro: macro, count: count, settings: settings, cancel: cancel,
                progress: { [weak self] iteration in self?.playbackProgressed(iteration, cancel) },
                completion: { [weak self] outcome in self?.playbackFinished(outcome, cancel) })
        }
    }
}
