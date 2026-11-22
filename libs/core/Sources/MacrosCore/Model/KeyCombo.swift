/// A physical key plus an exact modifier set, e.g. ⌃⌘M.
public struct KeyCombo: Hashable, Codable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = Modifiers(flags: modifiers.rawValue)
    }

    /// True when this is a non-repeating key-down of this key with exactly these modifiers.
    public func matches(_ event: MacroEvent) -> Bool {
        event.kind == .keyDown && event.isRepeat != true && event.keyCode == keyCode && event.modifiers == modifiers
    }

    /// A leader must include at least one of ⌘⌃⌥.
    public var isValidLeader: Bool { !modifiers.isDisjoint(with: .shortcutModifiers) }

    public static let defaultRecord = KeyCombo(keyCode: KeyCodes.m, modifiers: [.control, .command])
    public static let defaultPlay = KeyCombo(keyCode: KeyCodes.n, modifiers: [.control, .command])
}

/// macOS virtual key codes (ANSI layout positions).
public enum KeyCodes {
    public static let escape: UInt16 = 53
    public static let m: UInt16 = 46
    public static let n: UInt16 = 45

    /// The device-independent flag bit a modifier key controls, if it is one we track.
    public static func modifierFlag(forKeyCode code: UInt16) -> UInt64? {
        switch code {
        case 54, 55: Modifiers.command.rawValue
        case 56, 60: Modifiers.shift.rawValue
        case 58, 61: Modifiers.option.rawValue
        case 59, 62: Modifiers.control.rawValue
        case 63: 0x0080_0000  // fn
        default: nil
        }
    }
}
