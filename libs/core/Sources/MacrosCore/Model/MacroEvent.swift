/// One recorded input event. Stored flat (optional fields omitted when unused) so register files stay readable JSON.
public struct MacroEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case keyDown, keyUp, flagsChanged
        case mouseMove, mouseDown, mouseUp, mouseDrag
        case scroll
    }

    /// Milliseconds since the first event of the macro.
    public var t: Int
    public var kind: Kind
    /// Raw `CGEventFlags`.
    public var flags: UInt64
    public var keyCode: UInt16?
    public var isRepeat: Bool?
    /// Absolute global screen coordinates (top-left origin, as CoreGraphics reports them).
    public var x: Double?
    public var y: Double?
    /// 0 = left, 1 = right, 2+ = other.
    public var button: Int?
    public var clickCount: Int?
    public var scrollDX: Int32?
    public var scrollDY: Int32?

    public init(
        t: Int = 0,
        kind: Kind,
        flags: UInt64 = 0,
        keyCode: UInt16? = nil,
        isRepeat: Bool? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: Int? = nil,
        clickCount: Int? = nil,
        scrollDX: Int32? = nil,
        scrollDY: Int32? = nil
    ) {
        self.t = t
        self.kind = kind
        self.flags = flags
        self.keyCode = keyCode
        self.isRepeat = isRepeat
        self.x = x
        self.y = y
        self.button = button
        self.clickCount = clickCount
        self.scrollDX = scrollDX
        self.scrollDY = scrollDY
    }

    public var modifiers: Modifiers { Modifiers(flags: flags) }

    public static func key(_ kind: Kind, _ keyCode: UInt16, flags: UInt64 = 0, t: Int = 0) -> MacroEvent {
        MacroEvent(t: t, kind: kind, flags: flags, keyCode: keyCode)
    }

    public static func mouse(
        _ kind: Kind, x: Double, y: Double, button: Int = 0, clickCount: Int = 1, flags: UInt64 = 0, t: Int = 0
    ) -> MacroEvent {
        let hasButton = kind != .mouseMove
        return MacroEvent(
            t: t, kind: kind, flags: flags, x: x, y: y,
            button: hasButton ? button : nil, clickCount: hasButton ? clickCount : nil)
    }
}
