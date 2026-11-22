import CoreGraphics
import MacrosCore

/// Value stamped into `eventSourceUserData` on every event Macros posts, so the tap can tell them from real input.
enum SyntheticTag {
    static let value: Int64 = 0x4D_41_43_52_4F_53  // "MACROS"
}

extension CGEvent {
    var isMacrosSynthetic: Bool { getIntegerValueField(.eventSourceUserData) == SyntheticTag.value }
}

extension MacroEvent {
    /// Converts a tapped `CGEvent`. Returns `nil` for event types Macros doesn't record.
    init?(_ event: CGEvent, type: CGEventType) {
        let flags = event.flags.rawValue
        let location = event.location
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let clickCount = Int(event.getIntegerValueField(.mouseEventClickState))

        func mouse(_ kind: Kind) -> MacroEvent {
            .mouse(kind, x: location.x, y: location.y, button: button, clickCount: clickCount, flags: flags)
        }

        switch type {
        case .keyDown, .keyUp:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            self.init(
                kind: type == .keyDown ? .keyDown : .keyUp, flags: flags,
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                isRepeat: isRepeat ? true : nil)
        case .flagsChanged:
            self.init(
                kind: .flagsChanged, flags: flags, keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
        case .mouseMoved:
            self = .mouse(.mouseMove, x: location.x, y: location.y, flags: flags)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            self = mouse(.mouseDown)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            self = mouse(.mouseUp)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            self = mouse(.mouseDrag)
        case .scrollWheel:
            self.init(
                kind: .scroll, flags: flags, x: location.x, y: location.y,
                scrollDX: Int32(truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
                scrollDY: Int32(truncatingIfNeeded: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)))
        default:
            return nil
        }
    }

    /// Builds a tagged `CGEvent` ready to post.
    func makeCGEvent(source: CGEventSource?) -> CGEvent? {
        let point = CGPoint(x: x ?? 0, y: y ?? 0)
        let buttonNumber = button ?? 0
        let cgButton = CGMouseButton(rawValue: UInt32(min(buttonNumber, 2))) ?? .left

        func mouseType(left: CGEventType, right: CGEventType, other: CGEventType) -> CGEventType {
            switch buttonNumber {
            case 0: left
            case 1: right
            default: other
            }
        }

        let event: CGEvent?
        switch kind {
        case .keyDown, .keyUp:
            event = CGEvent(keyboardEventSource: source, virtualKey: keyCode ?? 0, keyDown: kind == .keyDown)
            if isRepeat == true { event?.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        case .flagsChanged:
            event = CGEvent(keyboardEventSource: source, virtualKey: keyCode ?? 0, keyDown: true)
            event?.type = .flagsChanged
        case .mouseMove:
            event = CGEvent(
                mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        case .mouseDown, .mouseUp, .mouseDrag:
            let type: CGEventType =
                switch kind {
                case .mouseDown: mouseType(left: .leftMouseDown, right: .rightMouseDown, other: .otherMouseDown)
                case .mouseUp: mouseType(left: .leftMouseUp, right: .rightMouseUp, other: .otherMouseUp)
                default: mouseType(left: .leftMouseDragged, right: .rightMouseDragged, other: .otherMouseDragged)
                }
            event = CGEvent(
                mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: cgButton)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(buttonNumber))
            event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount ?? 1))
        case .scroll:
            event = CGEvent(
                scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: scrollDY ?? 0, wheel2: scrollDX ?? 0, wheel3: 0)
        }

        event?.flags = CGEventFlags(rawValue: flags)
        event?.setIntegerValueField(.eventSourceUserData, value: SyntheticTag.value)
        return event
    }
}

/// Posts replayed events into the HID stream. Used only from the player thread.
final class CGEventSink: EventSink, @unchecked Sendable {
    private let source = CGEventSource(stateID: .hidSystemState)

    func post(_ event: MacroEvent) {
        event.makeCGEvent(source: source)?.post(tap: .cghidEventTap)
    }
}
