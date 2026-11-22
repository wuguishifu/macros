import AppKit
import ApplicationServices
import Carbon

enum Permissions {
    /// Accessibility access, needed for the active event tap and for posting events.
    static var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system "would like to control this computer" prompt (also adds Macros to the list in Settings).
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True while some app (e.g. a focused password field) has Secure Event Input on, hiding keystrokes from taps.
    static var isSecureInputActive: Bool { IsSecureEventInputEnabled() }
}
