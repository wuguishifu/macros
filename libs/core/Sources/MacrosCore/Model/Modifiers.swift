/// The device-independent modifier bits of `CGEventFlags` / `NSEvent.ModifierFlags` (they share values).
public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// Extracts the modifiers we care about from raw event flags.
    public init(flags: UInt64) { rawValue = flags & Modifiers.relevant.rawValue }

    public static let shift = Modifiers(rawValue: 0x0002_0000)
    public static let control = Modifiers(rawValue: 0x0004_0000)
    public static let option = Modifiers(rawValue: 0x0008_0000)
    public static let command = Modifiers(rawValue: 0x0010_0000)

    public static let relevant: Modifiers = [.shift, .control, .option, .command]
    /// Modifiers that make a key combo a "shortcut" (shift alone does not).
    public static let shortcutModifiers: Modifiers = [.control, .option, .command]

    /// Symbols in the conventional macOS order: ⌃⌥⇧⌘.
    public var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}
