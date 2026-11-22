import Testing

@testable import MacrosCore

private let register = Register("a")!

private func macro(_ times: [Int], trailing: Int) -> Macro {
    Macro(
        register: register, trailingGapMs: trailing,
        events: times.map { MacroEvent.key(.keyDown, Key.x, t: $0) })
}

@Suite struct ScheduleTests {
    @Test func realTimingByDefault() {
        let schedule = PlaybackSchedule(macro: macro([0, 100, 350], trailing: 50), settings: PlaybackSettings())
        #expect(schedule.entries.map(\.offsetNs) == [0, 100 * ms, 350 * ms])
        #expect(schedule.durationNs == 400 * ms)
    }

    @Test func speedDividesGaps() {
        let schedule = PlaybackSchedule(
            macro: macro([0, 100, 300], trailing: 100), settings: PlaybackSettings(speed: 2))
        #expect(schedule.entries.map(\.offsetNs) == [0, 50 * ms, 150 * ms])
        #expect(schedule.durationNs == 200 * ms)
    }

    @Test func idleCapShortensEachLongGapIncludingTrailing() {
        let schedule = PlaybackSchedule(
            macro: macro([0, 5_000, 5_100], trailing: 9_000), settings: PlaybackSettings(idleCapMs: 1_000))
        #expect(schedule.entries.map(\.offsetNs) == [0, 1_000 * ms, 1_100 * ms])
        #expect(schedule.durationNs == 2_100 * ms)
    }
}

@Suite struct PlayerTests {
    @Test func postsEventsOnScheduleAcrossIterationsWithGap() {
        let time = FakeTime()
        let sink = CapturingSink(time: time)
        let player = Player(sink: sink, time: time)
        let start = time.now()
        let progress = Collector<Int>()

        let outcome = player.run(
            macro: macro([0, 100], trailing: 50), count: 3,
            settings: PlaybackSettings(interIterationGapMs: 25), cancel: CancellationFlag(),
            progress: { progress.append($0) })

        #expect(outcome == .completed)
        #expect(progress.values == [1, 2, 3])
        // Iteration length 150ms + 25ms gap = 175ms.
        let offsets = sink.times.map { ($0 - start) / ms }
        #expect(offsets.prefix(6) == [0, 100, 175, 275, 350, 450])
    }

    @Test func releasesHeldKeysButtonsAndModifiersAtEnd() {
        let time = FakeTime()
        let sink = CapturingSink(time: time)
        let player = Player(sink: sink, time: time)
        let held = Macro(
            register: register, trailingGapMs: 0,
            events: [
                flagsEvent(Key.leftCmd, cmd),
                .key(.keyDown, Key.x, flags: cmd, t: 10),
                .mouse(.mouseDown, x: 40, y: 60, flags: cmd, t: 20),
            ])

        _ = player.run(macro: held, count: 1, settings: PlaybackSettings(), cancel: CancellationFlag())

        let releases = Array(sink.events.dropFirst(3))
        #expect(releases.map(\.kind) == [.keyUp, .mouseUp, .flagsChanged])
        #expect(releases[0].keyCode == Key.x)
        #expect(releases[1].x == 40 && releases[1].y == 60)
        #expect(releases[2].keyCode == Key.leftCmd && releases[2].modifiers.isEmpty)
    }

    @Test func abortStopsQuicklyAndStillReleases() {
        let time = FakeTime()
        let sink = CapturingSink(time: time)
        let player = Player(sink: sink, time: time)
        let cancel = CancellationFlag()
        let start = time.now()
        time.onSleep = { now in if now - start >= 500 * ms { cancel.cancel() } }

        let longMacro = Macro(
            register: register, trailingGapMs: 0,
            events: [.key(.keyDown, Key.x), .key(.keyUp, Key.x, t: 10_000)])
        let outcome = player.run(macro: longMacro, count: 5, settings: PlaybackSettings(), cancel: cancel)

        #expect(outcome == .aborted)
        #expect(sink.events.map(\.kind) == [.keyDown, .keyUp])  // the keyUp is the safety release
        #expect(time.now() - start < 600 * ms)
    }
}
