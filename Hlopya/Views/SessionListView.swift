import SwiftUI

/// Sidebar: record button + session list with status badges
struct SessionListView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            // Record controls
            recordButton
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Recording status
            if vm.audioCapture.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())
                    Text(vm.audioCapture.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            // Session list
            List(vm.sessionManager.sessions, selection: Binding(
                get: { vm.selectedSessionId },
                set: { id in if let id { vm.selectSession(id) } }
            )) { session in
                SessionRow(session: session, isProcessing: vm.processingSessionId == session.id)
                    .tag(session.id)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 240)
        .navigationTitle("Meetings")
    }

    private var recordButton: some View {
        Button {
            Task { await vm.toggleRecording() }
        } label: {
            HStack {
                Image(systemName: vm.audioCapture.isRecording ? "stop.fill" : "record.circle")
                Text(vm.audioCapture.isRecording ? "Stop" : "Record")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(vm.audioCapture.isRecording ? .red : .green)
        .controlSize(.large)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(Session.displayDateFormatter.string(from: session.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if session.duration > 0 {
                    Text("\(Int(session.duration / 60))m")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(
                    status: session.status,
                    isProcessing: isProcessing
                )
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: SessionStatus
    let isProcessing: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(bgColor.opacity(0.15))
            .foregroundStyle(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var label: String {
        if isProcessing { return "..." }
        switch status {
        case .recording: return "REC"
        case .recorded: return "REC"
        case .transcribed: return "STT"
        case .done: return "DONE"
        }
    }

    private var bgColor: Color {
        if isProcessing { return .purple }
        switch status {
        case .recording: return .red
        case .recorded: return .orange
        case .transcribed: return .cyan
        case .done: return .green
        }
    }
}

// MARK: - Pulse Animation

struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
