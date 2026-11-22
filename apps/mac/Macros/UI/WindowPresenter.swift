import AppKit
import SwiftUI

/// Shows SwiftUI views in reusable AppKit windows (simpler than SwiftUI scenes for a menu bar–only app).
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, content: () -> Content) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close(id: String) {
        windows[id]?.close()
    }
}
