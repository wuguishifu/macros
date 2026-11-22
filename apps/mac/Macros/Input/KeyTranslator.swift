import AppKit
import Carbon
import MacrosCore

/// Maps physical key codes to the characters they produce on the current keyboard layout (ignoring modifiers).
///
/// Built on the main thread; `character(for:)` is safe to call from the tap thread.
final class KeyTranslator: @unchecked Sendable {
    private let lock = NSLock()
    private var characters: [UInt16: Character] = [:]
    private var observer: NSObjectProtocol?

    @MainActor
    init() {
        rebuild()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    func character(for keyCode: UInt16) -> Character? {
        lock.withLock { characters[keyCode] }
    }

    /// Human-readable name for a key, e.g. "M", "Space", "F5".
    func displayName(for keyCode: UInt16) -> String {
        if let name = Self.specialNames[keyCode] { return name }
        if let character = character(for: keyCode) { return String(character).uppercased() }
        return "Key \(keyCode)"
    }

    func display(_ combo: KeyCombo) -> String {
        combo.modifiers.symbols + displayName(for: combo.keyCode)
    }

    @MainActor
    func rebuild() {
        let map = Self.layoutMap() ?? Self.ansiFallback
        lock.withLock { characters = map }
    }

    private static func layoutMap() -> [UInt16: Character]? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
                ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        return data.withUnsafeBytes { raw -> [UInt16: Character]? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var map: [UInt16: Character] = [:]
            for keyCode in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, buffer.count, &length, &buffer)
                guard status == noErr, length == 1 else { continue }
                let string = String(utf16CodeUnits: buffer, count: length).lowercased()
                guard let character = string.first, string.count == 1,
                    let scalar = character.unicodeScalars.first,
                    !CharacterSet.controlCharacters.contains(scalar), !character.isWhitespace
                else { continue }
                map[keyCode] = character
            }
            return map.isEmpty ? nil : map
        }
    }

    private static let ansiFallback: [UInt16: Character] = {
        let letters: [(UInt16, Character)] = [
            (0, "a"), (1, "s"), (2, "d"), (3, "f"), (4, "h"), (5, "g"), (6, "z"), (7, "x"), (8, "c"), (9, "v"),
            (11, "b"), (12, "q"), (13, "w"), (14, "e"), (15, "r"), (16, "y"), (17, "t"), (31, "o"), (32, "u"),
            (34, "i"), (35, "p"), (37, "l"), (38, "j"), (40, "k"), (45, "n"), (46, "m"),
        ]
        let digits: [(UInt16, Character)] = [
            (18, "1"), (19, "2"), (20, "3"), (21, "4"), (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"),
            (29, "0"), (82, "0"), (83, "1"), (84, "2"), (85, "3"), (86, "4"), (87, "5"), (88, "6"), (89, "7"),
            (91, "8"), (92, "9"),
        ]
        return Dictionary(uniqueKeysWithValues: letters + digits)
    }()

    private static let specialNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
