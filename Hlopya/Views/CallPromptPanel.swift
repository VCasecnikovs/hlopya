import SwiftUI
import AppKit

/// Floating prompt shown when MeetingDetector thinks a call has started.
/// "Record this call?" with Record / Not now / Don't ask for this app.
/// Mirrors RecordingNubPanel: borderless non-activating floating NSPanel.
final class CallPromptPanel: NSPanel {

    init(appName: String,
         onRecord: @escaping () -> Void,
         onDismiss: @escaping () -> Void,
         onBlacklist: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        // Top-right corner, just below the menu bar.
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 320 - 16
            let y = screen.visibleFrame.maxY - 110 - 12
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        let content = CallPromptContent(
            appName: appName,
            onRecord: onRecord,
            onDismiss: onDismiss,
            onBlacklist: onBlacklist
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 110)
        contentView = hosting
    }
}

private struct CallPromptContent: View {
    let appName: String
    let onRecord: () -> Void
    let onDismiss: () -> Void
    let onBlacklist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HlopSpacing.md) {
            HStack(spacing: HlopSpacing.sm) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(HlopColors.recordingBadge)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Record this call?")
                        .font(HlopTypography.body).fontWeight(.semibold)
                    Text("\(appName) is using your microphone")
                        .font(HlopTypography.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: HlopSpacing.sm) {
                Button(action: onRecord) {
                    Label("Record", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Button(action: onBlacklist) {
                Text("Don’t ask for \(appName)")
                    .font(HlopTypography.footnote)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(HlopSpacing.md)
        .frame(width: 320)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        }
    }
}
