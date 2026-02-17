import SwiftUI

/// Sidebar: record button + session list with status badges
struct SessionListView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var sessionToDelete: Session?
    @State private var meetingWith: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Meeting participant input
            if !vm.audioCapture.isRecording {
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Meeting with...", text: $meetingWith)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

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
                    if !meetingWith.isEmpty {
                        Text("with \(meetingWith)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            // Permission error
            if let error = vm.audioCapture.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12)
                .onTapGesture {
                    vm.audioCapture.lastError = nil
                }
            }

            Divider()

            // Session list
            List(vm.sessionManager.sessions, selection: Binding(
                get: { vm.selectedSessionId },
                set: { id in if let id { vm.selectSession(id) } }
            )) { session in
                SessionRow(session: session, isProcessing: vm.processingSessionId == session.id)
                    .tag(session.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            sessionToDelete = session
                        }
                    }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 240)
        .navigationTitle("Meetings")
        .alert("Delete Recording?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let s = sessionToDelete {
                    vm.deleteSession(s.id)
                    sessionToDelete = nil
                }
            }
        } message: {
            Text("This will permanently delete the recording and all associated files.")
        }
    }

    private var recordButton: some View {
        Button {
            Task {
                if !vm.audioCapture.isRecording && !meetingWith.isEmpty {
                    vm.pendingParticipant = meetingWith
                }
                await vm.toggleRecording()
                if !vm.audioCapture.isRecording {
                    meetingWith = ""
                }
            }
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
