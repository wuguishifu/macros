import Foundation
import Testing

@testable import MacrosCore

@Suite struct StorageTests {
    private func tempStore() -> RegisterStore {
        RegisterStore(directory: FileManager.default.temporaryDirectory.appending(path: "macros-tests-\(UUID())"))
    }

    @Test func roundTripsMacros() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let macro = Macro(
            register: Register("q")!, label: "github", recordedAt: Date(timeIntervalSince1970: 1_800_000_000),
            trailingGapMs: 850,
            events: [
                .mouse(.mouseDown, x: 812.5, y: 440, button: 0, clickCount: 2, t: 0),
                .key(.keyDown, 48, flags: Modifiers.control.rawValue, t: 310),
                MacroEvent(t: 400, kind: .scroll, scrollDX: -3, scrollDY: 12),
            ])
        try store.save(macro)
        #expect(store.loadAll() == [Register("q")!: macro])

        try store.delete(Register("q")!)
        #expect(store.loadAll().isEmpty)
    }

    @Test func omitsUnusedFieldsInJSON() throws {
        let data = try RegisterStore.makeEncoder().encode(MacroEvent.key(.keyDown, 48, t: 5))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("\"x\""))
        #expect(json.contains("\"keyCode\" : 48"))
    }

    @Test func skipsNewerSchemaAndCorruptFiles() throws {
        let store = tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var future = Macro(register: Register("a")!, trailingGapMs: 0, events: [.key(.keyDown, 1)])
        future.schemaVersion = Macro.currentSchemaVersion + 1
        try store.save(future)
        try Data("not json".utf8).write(to: store.fileURL(for: Register("b")!))
        #expect(store.loadAll().isEmpty)
    }

    @Test func registersParseLettersOnly() {
        #expect(Register("A")?.letter == "a")
        #expect(Register("1") == nil)
        #expect(Register("é") == nil)
        #expect(Register.all.count == 26)
    }
}
