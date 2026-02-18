import SwiftUI

/// Sidebar: record button + session list with status badges
struct SessionListView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var sessionToDelete: Session?
    @State private var meetingWith: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Record controls area - fixed height to avoid layout changes
            VStack(spacing: 10) {
                // Meeting participant input
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 12))
                    TextField("Meeting with...", text: $meetingWith)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .disabled(vm.audioCapture.isRecording)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(vm.audioCapture.isRecording ? 0.4 : 1)

                // Record button
                Button {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        Task {
                            if !vm.audioCapture.isRecording && !meetingWith.isEmpty {
                                vm.pendingParticipant = meetingWith
                            }
                            await vm.toggleRecording()
                            if !vm.audioCapture.isRecording {
                                meetingWith = ""
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: vm.audioCapture.isRecording ? "stop.fill" : "record.circle")
                            .font(.system(size: 14))
                        Text(vm.audioCapture.isRecording ? "Stop Recording" : "Record")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.audioCapture.isRecording ? .red : .accentColor)
                .controlSize(.large)

                // Recording indicator - always in layout, shown via opacity
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                        .modifier(PulseAnimation())
                    Text(vm.audioCapture.formattedTime)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    if !meetingWith.isEmpty {
                        Text("with \(meetingWith)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .frame(height: 20)
                .opacity(vm.audioCapture.isRecording ? 1 : 0)
            }
            .padding(14)

            // Error banner
            if let error = vm.audioCapture.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button {
                        vm.audioCapture.lastError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Divider()

            // Session list
            List(vm.sessionManager.sessions, selection: Binding(
                get: { vm.selectedSessionId },
                set: { id in if let id { vm.selectSession(id) } }
            )) { session in
                SessionRow(
                    session: session,
                    isProcessing: vm.processingSessionId == session.id,
                    onDelete: { sessionToDelete = session }
                )
                .tag(session.id)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        sessionToDelete = session
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    let isProcessing: Bool
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)

                Spacer(minLength: 4)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }

            HStack(spacing: 6) {
                Text(Session.displayDateFormatter.string(from: session.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                if session.duration > 0 {
                    Text("\(Int(session.duration / 60))m")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                StatusBadge(
                    status: session.status,
                    isProcessing: isProcessing
                )
            }
        }
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: SessionStatus
    let isProcessing: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bgColor.opacity(0.15))
            .foregroundStyle(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var label: String {
        if isProcessing { return "..." }
        switch status {
        case .recording: return "REC"
        case .recorded: return "NEW"
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
