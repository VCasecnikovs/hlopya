import SwiftUI

/// Main window: NavigationSplitView with sidebar (sessions) + detail (transcript/notes)
struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm

        VStack(spacing: 0) {
            NavigationSplitView {
                SessionListView()
            } detail: {
                if vm.selectedSessionId != nil {
                    SessionDetailView()
                } else {
                    emptyState
                }
            }
            .navigationSplitViewStyle(.balanced)

            // Status bar
            statusBar
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if let session = vm.selectedSession {
                Text(session.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusText: String {
        if vm.audioCapture.isRecording {
            return "Recording - \(vm.audioCapture.formattedTime)"
        } else if vm.isProcessing {
            return "Processing..."
        } else if let session = vm.selectedSession {
            switch session.status {
            case .recording: return "Recording"
            case .recorded: return "Ready to process"
            case .transcribed: return "Transcribed - ready for notes"
            case .done: return "Complete"
            }
        }
        return "Ready"
    }

    private var statusColor: Color {
        if vm.audioCapture.isRecording { return .red }
        if vm.isProcessing { return .purple }
        if let session = vm.selectedSession {
            switch session.status {
            case .recording: return .red
            case .recorded: return .orange
            case .transcribed: return .cyan
            case .done: return .green
            }
        }
        return .gray
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Record a meeting to get started")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
