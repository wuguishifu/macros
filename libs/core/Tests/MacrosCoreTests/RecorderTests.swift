import Testing

@testable import MacrosCore

@Suite struct RecorderTests {
    @Test func rebasesTimestampsAndMeasuresTrailingGap() throws {
        let recorder = Recorder(startModifiers: [])
        recorder.record(.key(.keyDown, Key.x), at: 500 * ms)
        recorder.record(.key(.keyUp, Key.x), at: 600 * ms)
        let result = try #require(recorder.finish(stopAt: 1_400 * ms, leaderModifiers: [.control, .command]))
        #expect(result.events.map(\.t) == [0, 100])
        #expect(result.trailingGapMs == 800)
    }

    @Test func dropsLeadingReleasesOfStartChordModifiers() throws {
        let recorder = Recorder(startModifiers: [.control, .command])
        recorder.record(flagsEvent(Key.leftCtrl, cmd), at: 10 * ms)  // ⌃ released
        recorder.record(.mouse(.mouseMove, x: 1, y: 1), at: 15 * ms)
        recorder.record(flagsEvent(Key.leftCmd, 0), at: 20 * ms)  // ⌘ released
        recorder.record(.key(.keyDown, Key.x), at: 30 * ms)
        let result = try #require(recorder.finish(stopAt: 40 * ms, leaderModifiers: [.control, .command]))
        #expect(result.events.map(\.kind) == [.mouseMove, .keyDown])
    }

    @Test func keepsModifierPressesAfterFirstRealEvent() throws {
        let recorder = Recorder(startModifiers: [])
        recorder.record(flagsEvent(Key.leftShift, shift), at: 10 * ms)
        recorder.record(.key(.keyDown, Key.x, flags: shift), at: 20 * ms)
        recorder.record(flagsEvent(Key.leftShift, 0), at: 30 * ms)
        recorder.record(.key(.keyDown, Key.tab), at: 40 * ms)
        let result = try #require(recorder.finish(stopAt: 50 * ms, leaderModifiers: [.control, .command]))
        #expect(result.events.count == 4)
    }

    @Test func stripsTrailingStopLeaderModifierPresses() throws {
        let recorder = Recorder(startModifiers: [])
        recorder.record(.key(.keyDown, Key.tab, flags: ctrl), at: 100 * ms)
        recorder.record(.key(.keyUp, Key.tab, flags: ctrl), at: 150 * ms)
        recorder.record(flagsEvent(Key.leftCtrl, 0), at: 200 * ms)  // release ⌃ (a release, kept)
        recorder.record(flagsEvent(Key.leftCtrl, ctrl), at: 900 * ms)  // stop chord begins
        recorder.record(.mouse(.mouseMove, x: 5, y: 5), at: 950 * ms)
        recorder.record(flagsEvent(Key.leftCmd, ctrl | cmd), at: 1_000 * ms)
        let result = try #require(recorder.finish(stopAt: 1_100 * ms, leaderModifiers: [.control, .command]))
        #expect(result.events.map(\.kind) == [.keyDown, .keyUp, .flagsChanged])
        #expect(result.events.last?.flags == 0)
        // Trailing gap runs to the first stripped press, not to the stop key.
        #expect(result.trailingGapMs == 700)
    }

    @Test func emptyRecordingReturnsNil() {
        let recorder = Recorder(startModifiers: [])
        recorder.record(flagsEvent(Key.leftCtrl, ctrl), at: 10 * ms)
        recorder.record(flagsEvent(Key.leftCmd, ctrl | cmd), at: 20 * ms)
        #expect(recorder.finish(stopAt: 30 * ms, leaderModifiers: [.control, .command]) == nil)
        #expect(Recorder(startModifiers: []).finish(stopAt: 0, leaderModifiers: [.command]) == nil)
    }
}
