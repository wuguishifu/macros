import Foundation
import MacrosCore
import Observation
import ServiceManagement
import os

private let logger = Logger(subsystem: "dev.wuguishifu.macros", category: "settings")

/// User preferences, persisted in `UserDefaults`.
@MainActor @Observable
final class AppSettings {
    static let speedOptions: [Double] = [1, 2, 4]
    /// Seconds; 0 = off.
    static let idleCapOptions: [Int] = [0, 1, 3, 5]
    static let chordTimeoutOptions: [Double] = [1, 2, 3, 5, 10]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    var recordLeader: KeyCombo { didSet { store(recordLeader, "recordLeader") } }
    var playLeader: KeyCombo { didSet { store(playLeader, "playLeader") } }
    var chordTimeoutSeconds: Double { didSet { store(chordTimeoutSeconds, "chordTimeoutSeconds") } }
    var speed: Double { didSet { store(speed, "speed") } }
    var idleCapSeconds: Int { didSet { store(idleCapSeconds, "idleCapSeconds") } }
    var interIterationGapMs: Int { didSet { store(interIterationGapMs, "interIterationGapMs") } }

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return SMAppService.mainApp.status == .enabled
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    logger.error("Launch at login change failed: \(error)")
                }
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recordLeader = Self.load(KeyCombo.self, "recordLeader", defaults) ?? .defaultRecord
        playLeader = Self.load(KeyCombo.self, "playLeader", defaults) ?? .defaultPlay
        chordTimeoutSeconds = Self.load(Double.self, "chordTimeoutSeconds", defaults) ?? 3
        speed = Self.load(Double.self, "speed", defaults) ?? 1
        idleCapSeconds = Self.load(Int.self, "idleCapSeconds", defaults) ?? 0
        interIterationGapMs = Self.load(Int.self, "interIterationGapMs", defaults) ?? 0
    }

    var engineConfig: EngineConfig {
        EngineConfig(
            recordLeader: recordLeader,
            playLeader: playLeader,
            chordTimeoutMs: Int(chordTimeoutSeconds * 1000),
            playback: PlaybackSettings(
                speed: speed,
                idleCapMs: idleCapSeconds > 0 ? idleCapSeconds * 1000 : nil,
                interIterationGapMs: max(0, interIterationGapMs)))
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        onChange?()
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
