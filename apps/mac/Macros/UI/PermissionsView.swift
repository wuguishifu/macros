import SwiftUI

struct PermissionsView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Macros needs Accessibility access", systemImage: "hand.raised.fill")
                .font(.headline)

            Text(
                "Macros listens for its shortcuts and records and replays keyboard and mouse input. "
                    + "macOS only allows that for apps you approve under Privacy & Security → Accessibility."
            )
            .fixedSize(horizontal: false, vertical: true)

            Text("Recordings stay on this Mac. Macros never sends input anywhere.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Label(
                    model.accessibilityGranted ? "Granted" : "Not granted yet",
                    systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle"
                )
                .foregroundStyle(model.accessibilityGranted ? .green : .secondary)
                Spacer()
                Button("Open Privacy Settings") { Permissions.openAccessibilitySettings() }
                Button("Request Access") { Permissions.requestAccessibility() }
                    .keyboardShortcut(.defaultAction)
            }

            Text("This window closes automatically once access is granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
