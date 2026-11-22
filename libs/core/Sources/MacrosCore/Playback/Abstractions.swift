import Foundation

/// Where replayed events go. The app implements this with `CGEvent.post`.
public protocol EventSink: Sendable {
    func post(_ event: MacroEvent)
}

/// A monotonic clock in nanoseconds. (Not named `Clock` to avoid clashing with the standard library.)
public protocol TimeSource: Sendable {
    func now() -> UInt64
    func sleep(until deadline: UInt64)
}

public struct SystemTimeSource: TimeSource {
    public init() {}

    public func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    public func sleep(until deadline: UInt64) {
        let current = now()
        guard deadline > current else { return }
        let delta = deadline - current
        var request = timespec(tv_sec: Int(delta / 1_000_000_000), tv_nsec: Int(delta % 1_000_000_000))
        nanosleep(&request, nil)
    }
}

/// A thread-safe one-way flag used to abort playback.
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func cancel() { lock.withLock { cancelled = true } }
}

public enum PlaybackOutcome: Sendable, Equatable {
    case completed
    case aborted
}

/// Starts playback somewhere off the caller's thread.
public protocol PlaybackRunner: Sendable {
    func start(
        macro: Macro,
        count: Int,
        settings: PlaybackSettings,
        cancel: CancellationFlag,
        progress: @escaping @Sendable (Int) -> Void,
        completion: @escaping @Sendable (PlaybackOutcome) -> Void
    )
}

/// Runs each playback on its own high-priority thread.
public struct ThreadPlaybackRunner: PlaybackRunner {
    private let player: Player

    public init(player: Player) {
        self.player = player
    }

    public func start(
        macro: Macro,
        count: Int,
        settings: PlaybackSettings,
        cancel: CancellationFlag,
        progress: @escaping @Sendable (Int) -> Void,
        completion: @escaping @Sendable (PlaybackOutcome) -> Void
    ) {
        let player = self.player
        let thread = Thread {
            let outcome = player.run(macro: macro, count: count, settings: settings, cancel: cancel, progress: progress)
            completion(outcome)
        }
        thread.name = "dev.wuguishifu.macros.player"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}
