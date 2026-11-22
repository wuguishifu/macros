import Foundation
import os

private let logger = Logger(subsystem: "dev.wuguishifu.macros", category: "storage")

/// Reads and writes one JSON file per register.
public struct RegisterStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Macros/registers`
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory
            .appending(path: "Macros", directoryHint: .isDirectory)
            .appending(path: "registers", directoryHint: .isDirectory)
    }

    public func fileURL(for register: Register) -> URL {
        directory.appending(path: "\(register).json", directoryHint: .notDirectory)
    }

    public func loadAll() -> [Register: Macro] {
        var result: [Register: Macro] = [:]
        let decoder = Self.makeDecoder()
        for register in Register.all {
            let url = fileURL(for: register)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                let macro = try decoder.decode(Macro.self, from: Data(contentsOf: url))
                guard macro.schemaVersion <= Macro.currentSchemaVersion else {
                    logger.warning("Skipping \(url.lastPathComponent): schema \(macro.schemaVersion) is newer")
                    continue
                }
                result[register] = macro
            } catch {
                logger.error("Failed to load \(url.lastPathComponent): \(error)")
            }
        }
        return result
    }

    public func save(_ macro: Macro) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(macro)
        try data.write(to: fileURL(for: macro.register), options: .atomic)
    }

    public func delete(_ register: Register) throws {
        let url = fileURL(for: register)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The in-memory set of registers, persisted asynchronously. Safe to use from any thread.
public final class RegisterBank: @unchecked Sendable {
    private let lock = NSLock()
    private var macros: [Register: Macro]
    private var changeHandler: (@Sendable () -> Void)?
    private let store: RegisterStore?
    private let ioQueue = DispatchQueue(label: "dev.wuguishifu.macros.storage", qos: .utility)

    /// - Parameter store: `nil` keeps registers in memory only (tests).
    public init(store: RegisterStore?) {
        self.store = store
        macros = store?.loadAll() ?? [:]
    }

    public func onChange(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { changeHandler = handler }
    }

    public func macro(for register: Register) -> Macro? {
        lock.withLock { macros[register] }
    }

    public var all: [Macro] {
        lock.withLock { macros.values.sorted { $0.register < $1.register } }
    }

    public func set(_ macro: Macro) {
        let handler = lock.withLock {
            macros[macro.register] = macro
            return changeHandler
        }
        persist { try $0.save(macro) }
        handler?()
    }

    public func remove(_ register: Register) {
        let handler = lock.withLock {
            macros[register] = nil
            return changeHandler
        }
        persist { try $0.delete(register) }
        handler?()
    }

    public func setLabel(_ label: String?, for register: Register) {
        let updated: Macro? = lock.withLock {
            guard var macro = macros[register] else { return nil }
            macro.label = label
            macros[register] = macro
            return macro
        }
        if let updated { set(updated) }
    }

    private func persist(_ operation: @escaping @Sendable (RegisterStore) throws -> Void) {
        guard let store else { return }
        ioQueue.async {
            do {
                try operation(store)
            } catch {
                logger.error("Failed to persist register: \(error)")
            }
        }
    }
}
