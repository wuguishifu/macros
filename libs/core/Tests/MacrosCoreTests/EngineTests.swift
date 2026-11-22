import Testing

@testable import MacrosCore

/// Drives a `MacroEngine` with a keyboard simulation and in-memory registers.
private final class Harness {
    let bank = RegisterBank(store: nil)
    let runner = FakeRunner()
    let notices = Collector<String>()
    let statuses = Collector<EngineStatus>()
    let engine: MacroEngine
    var now: UInt64 = 1_000 * ms
    var flags: UInt64 = 0

    init(config: EngineConfig = EngineConfig()) {
        let notices = notices
        let statuses = statuses
        engine = MacroEngine(
            bank: bank, runner: runner, config: config,
            onStatus: { statuses.append($0) }, onNotice: { notices.append($0) })
    }

    @discardableResult
    func send(_ event: MacroEvent, character: Character? = nil, synthetic: Bool = false, after delayMs: UInt64 = 10)
        -> TapDecision
    {
        now += delayMs * ms
        var event = event
        event.flags = event.kind == .flagsChanged ? event.flags : flags
        return engine.handle(InputEvent(event: event, timestamp: now, character: character, isSynthetic: synthetic))
    }

    /// Presses and releases modifier keys, returning each decision.
    func press(_ modifiers: [(UInt16, UInt64)]) -> [TapDecision] {
        modifiers.map { code, flag in
            flags |= flag
            return send(flagsEvent(code, flags))
        }
    }

    func release(_ modifiers: [(UInt16, UInt64)]) -> [TapDecision] {
        modifiers.map { code, flag in
            flags &= ~flag
            return send(flagsEvent(code, flags))
        }
    }

    /// Key down + up. Returns (down, up) decisions.
    @discardableResult
    func tap(_ code: UInt16, _ character: Character? = nil) -> (TapDecision, TapDecision) {
        let down = send(.key(.keyDown, code), character: character)
        let up = send(.key(.keyUp, code))
        return (down, up)
    }

    /// Types ⌃⌘<key> the way a person does: press ⌃, ⌘, key, release key, release ⌘ ⌃.
    func chord(_ code: UInt16) -> [TapDecision] {
        var decisions = press([(Key.leftCtrl, ctrl), (Key.leftCmd, cmd)])
        let (down, up) = tap(code)
        decisions += [down, up]
        decisions += release([(Key.leftCmd, cmd), (Key.leftCtrl, ctrl)])
        return decisions
    }

    func record(_ register: Character, shiftForAppend: Bool = false, body: () -> Void) {
        _ = chord(KeyCodes.m)
        if shiftForAppend {
            _ = press([(Key.leftShift, shift)])
            tap(Key.a, register)
            _ = release([(Key.leftShift, shift)])
        } else {
            tap(Key.a, register)
        }
        body()
        now += 500 * ms
        _ = chord(KeyCodes.m)
    }
}

@Suite struct EngineRecordingTests {
    @Test func recordsBodyAndSwallowsOnlyChordKeys() throws {
        let h = Harness()
        let leader = h.chord(KeyCodes.m)
        // Modifiers pass through, M down/up swallowed.
        #expect(leader == [.pass, .pass, .swallow, .swallow, .pass, .pass])
        #expect(h.engine.status == .pendingRecord)

        #expect(h.tap(Key.a, "a") == (.swallow, .swallow))
        #expect(h.engine.status == .recording(Register("a")!, appending: false))

        #expect(h.tap(Key.x, "x") == (.pass, .pass))
        #expect(h.send(.mouse(.mouseMove, x: 10, y: 20)) == .pass)

        h.now += 700 * ms
        let stop = h.chord(KeyCodes.m)
        #expect(stop == [.pass, .pass, .swallow, .swallow, .pass, .pass])
        #expect(h.engine.status == .idle)

        let macro = try #require(h.bank.macro(for: Register("a")!))
        #expect(macro.events.map(\.kind) == [.keyDown, .keyUp, .mouseMove])
        #expect(macro.events.first?.t == 0)
        #expect(macro.trailingGapMs == 710)
        #expect(h.notices.values == ["Recorded @a"])
    }

    @Test func dropsStartChordModifierReleasesFromRecording() throws {
        let h = Harness()
        _ = h.press([(Key.leftCtrl, ctrl), (Key.leftCmd, cmd)])
        h.tap(KeyCodes.m)
        h.tap(Key.a, "a")  // still holding ⌃⌘
        _ = h.release([(Key.leftCmd, cmd), (Key.leftCtrl, ctrl)])
        h.tap(Key.x, "x")
        _ = h.chord(KeyCodes.m)
        let macro = try #require(h.bank.macro(for: Register("a")!))
        #expect(macro.events.map(\.kind) == [.keyDown, .keyUp])
    }

    @Test func emptyRecordingLeavesRegisterUnchanged() throws {
        let h = Harness()
        h.record("a") { h.tap(Key.x, "x") }
        let original = try #require(h.bank.macro(for: Register("a")!))

        h.record("a") {}
        #expect(h.bank.macro(for: Register("a")!) == original)
        #expect(h.notices.values.last == "Empty recording — @a unchanged")
    }

    @Test func shiftLetterAppends() throws {
        let h = Harness()
        h.record("a") { h.tap(Key.x, "x") }
        h.record("a", shiftForAppend: true) { h.tap(Key.b, "b") }
        let macro = try #require(h.bank.macro(for: Register("a")!))
        #expect(macro.events.compactMap(\.keyCode) == [Key.x, Key.x, Key.b, Key.b])
        #expect(macro.events[2].t > macro.events[1].t)
        #expect(h.notices.values.last == "Appended to @a")
    }

    @Test func playLeaderIgnoredWhileRecording() throws {
        let h = Harness()
        h.record("a") {
            h.tap(Key.x, "x")
            #expect(h.send(.key(.keyDown, KeyCodes.n, flags: 0)) == .pass)  // plain N is just typing
            h.flags = ctrl | cmd
            #expect(h.send(.key(.keyDown, KeyCodes.n)) == .swallow)
            #expect(h.send(.key(.keyUp, KeyCodes.n)) == .swallow)
            h.flags = 0
        }
        #expect(h.notices.values.contains("Can't play while recording"))
        #expect(h.runner.invocations.isEmpty)
        let macro = try #require(h.bank.macro(for: Register("a")!))
        #expect(!macro.events.contains { $0.keyCode == KeyCodes.n && $0.flags == ctrl | cmd })
    }

    @Test func escapeAndTimeoutCancelPendingRecord() {
        let h = Harness(config: EngineConfig(chordTimeoutMs: 3000))
        _ = h.chord(KeyCodes.m)
        #expect(h.tap(KeyCodes.escape) == (.swallow, .swallow))
        #expect(h.engine.status == .idle)

        _ = h.chord(KeyCodes.m)
        h.engine.tick(now: h.now + 2_000 * ms)
        #expect(h.engine.status == .pendingRecord)
        h.engine.tick(now: h.now + 3_100 * ms)
        #expect(h.engine.status == .idle)
    }

    @Test func nonLetterCancelsWithNotice() {
        let h = Harness()
        _ = h.chord(KeyCodes.m)
        #expect(h.tap(Key.one, "1") == (.swallow, .swallow))
        #expect(h.engine.status == .idle)
        #expect(h.notices.values == ["Not a register — recording cancelled"])
    }
}

@Suite struct EnginePlaybackTests {
    private func harnessWithMacro() -> Harness {
        let h = Harness()
        h.record("a") { h.tap(Key.x, "x") }
        return h
    }

    @Test func playsOnce() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        #expect(h.tap(Key.a, "a") == (.swallow, .swallow))
        let run = try #require(h.runner.invocations.first)
        #expect(run.count == 1)
        #expect(run.macro.register == Register("a")!)
        #expect(h.engine.status == .playing(Register("a")!, iteration: 1, total: 1))

        run.progress(1)
        run.completion(.completed)
        #expect(h.engine.status == .idle)
    }

    @Test func countDigitsAreCappedAtThree() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        h.tap(Key.one, "1")
        h.tap(Key.two, "2")
        #expect(h.engine.status == .pendingPlay(count: "12"))
        h.tap(Key.one, "1")
        h.tap(Key.two, "2")
        #expect(h.engine.status == .pendingPlay(count: "121"))
        h.tap(Key.a, "a")
        #expect(try #require(h.runner.invocations.first).count == 121)
    }

    @Test func doubleLeaderReplaysLast() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        _ = h.chord(KeyCodes.n)
        #expect(h.engine.status == .idle)
        #expect(h.notices.values.last == "Nothing played yet")

        _ = h.chord(KeyCodes.n)
        h.tap(Key.a, "a")
        h.runner.invocations[0].completion(.completed)

        _ = h.chord(KeyCodes.n)
        h.tap(Key.two, "2")
        _ = h.chord(KeyCodes.n)
        let replay = try #require(h.runner.invocations.last)
        #expect(h.runner.invocations.count == 2)
        #expect(replay.macro.register == Register("a")!)
        #expect(replay.count == 2)
    }

    @Test func emptyRegisterShowsNotice() {
        let h = Harness()
        _ = h.chord(KeyCodes.n)
        h.tap(Key.b, "b")
        #expect(h.runner.invocations.isEmpty)
        #expect(h.notices.values == ["@b is empty"])
        #expect(h.engine.status == .idle)
    }

    @Test func physicalInputBlockedAndSyntheticPassesDuringPlayback() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        h.tap(Key.a, "a")

        #expect(h.tap(Key.x, "x") == (.swallow, .swallow))
        #expect(h.send(.mouse(.mouseDown, x: 1, y: 1)) == .swallow)
        #expect(h.send(.key(.keyDown, Key.x), synthetic: true) == .pass)
        #expect(h.chord(KeyCodes.m).allSatisfy { $0 == .swallow })
    }

    @Test func escapeAbortsPlayback() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        h.tap(Key.a, "a")
        let run = try #require(h.runner.invocations.first)

        #expect(h.tap(KeyCodes.escape) == (.swallow, .swallow))
        #expect(run.cancel.isCancelled)
        run.completion(.aborted)
        #expect(h.engine.status == .idle)
        #expect(h.notices.values.last == "Playback stopped")
    }

    @Test func playLeaderAbortsPlayback() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        h.tap(Key.a, "a")
        _ = h.chord(KeyCodes.n)
        #expect(try #require(h.runner.invocations.first).cancel.isCancelled)
    }

    @Test func progressUpdatesStatus() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        h.tap(Key.three, "3")
        h.tap(Key.a, "a")
        let run = try #require(h.runner.invocations.first)
        run.progress(2)
        #expect(h.engine.status == .playing(Register("a")!, iteration: 2, total: 3))
        #expect(h.statuses.values.contains(.playing(Register("a")!, iteration: 2, total: 3)))
    }

    @Test func suspendedPassesEverythingAndAbortsPlayback() throws {
        let h = harnessWithMacro()
        _ = h.chord(KeyCodes.n)
        h.tap(Key.a, "a")
        let run = try #require(h.runner.invocations.first)
        h.engine.setSuspended(true)
        #expect(run.cancel.isCancelled)
        #expect(h.engine.status == .suspended)
        #expect(h.chord(KeyCodes.m).allSatisfy { $0 == .pass })
        // A late completion from the aborted run doesn't disturb state.
        run.completion(.aborted)
        #expect(h.engine.status == .suspended)
    }
}

extension Key {
    static let three: UInt16 = 20
}
