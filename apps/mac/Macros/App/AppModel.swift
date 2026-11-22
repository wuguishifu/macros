import Foundation
import MacrosCore
import Observation

/// UI-facing state, updated on the main thread from engine callbacks and polling.
@MainActor @Observable
final class AppModel {
    var status: EngineStatus = .idle { didSet { onHUDChange?() } }
    var notice: String? { didSet { onHUDChange?() } }
    var secureInputActive = false { didSet { onHUDChange?() } }
    var accessibilityGranted = false
    var tapFailed = false
    var registers: [Macro] = []

    @ObservationIgnored var onHUDChange: (() -> Void)?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    var hudVisible: Bool {
        switch status {
        case .idle, .suspended: notice != nil
        default: true
        }
    }

    var isRecording: Bool {
        if case .recording = status { true } else { false }
    }

    var menuBarSymbol: String {
        if !accessibilityGranted || tapFailed { return "exclamationmark.triangle" }
        switch status {
        case .idle, .suspended: return "keyboard"
        case .pendingRecord, .pendingPlay: return "ellipsis.circle"
        case .recording: return "record.circle.fill"
        case .playing: return "play.circle.fill"
        }
    }
}
