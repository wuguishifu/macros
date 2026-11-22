import AppKit
import MacrosCore
import SwiftUI

/// A click-through floating panel in the top-right corner of the main screen.
@MainActor
final class HUDController {
    private static let size = NSSize(width: 360, height: 120)
    private static let margin: CGFloat = 12

    private let model: AppModel
    private let panel: NSPanel

    init(model: AppModel, translator: KeyTranslator, settings: AppSettings) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(
            rootView: HUDView(model: model, translator: translator, settings: settings)
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topTrailing))
    }

    func update() {
        guard model.hudVisible else {
            panel.orderOut(nil)
            return
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(x: frame.maxX - Self.size.width - Self.margin, y: frame.maxY - Self.size.height - Self.margin))
        }
        panel.orderFrontRegardless()
    }
}

struct HUDView: View {
    let model: AppModel
    let translator: KeyTranslator
    let settings: AppSettings

    var body: some View {
        if model.hudVisible {
            VStack(alignment: .trailing, spacing: 4) {
                if let title {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if model.secureInputActive {
                    Label("Secure input active — keys not captured", systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }
                if let notice = model.notice, title != nil {
                    Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.6), lineWidth: 1)
            )
            .padding(4)
        }
    }

    private var title: String? {
        switch model.status {
        case .idle, .suspended: model.notice
        case .pendingRecord: "● Record into…"
        case .recording(let register, let appending): "● REC @\(register)\(appending ? " (append)" : "")"
        case .pendingPlay(let count): "▶ Play \(count)_"
        case .playing(let register, let iteration, let total):
            total > 1 ? "▶ @\(register)  \(iteration)/\(total)" : "▶ @\(register)"
        }
    }

    private var subtitle: String? {
        switch model.status {
        case .idle, .suspended: nil
        case .pendingRecord: "a–z to record · ⇧ to append · ⎋ cancel"
        case .recording: "\(translator.display(settings.recordLeader)) to stop"
        case .pendingPlay: "count, then a–z · \(translator.display(settings.playLeader)) for last · ⎋ cancel"
        case .playing: "⎋ to stop"
        }
    }

    private var accent: Color {
        switch model.status {
        case .recording, .pendingRecord: .red
        case .playing, .pendingPlay: .green
        case .idle, .suspended: .secondary
        }
    }
}
