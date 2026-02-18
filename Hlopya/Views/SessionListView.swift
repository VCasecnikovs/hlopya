import SwiftUI

/// Sidebar: record button + session list with status badges
struct SessionListView: View {
    @Environment(AppViewModel.self) private var vm
    @Binding var showVocabulary: Bool
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
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
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
                .shimmer(isActive: vm.audioCapture.isRecording)
                .accessibilityLabel(vm.audioCapture.isRecording ? "Stop recording" : "Start recording")
                .accessibilityHint("Double-tap to toggle recording")

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
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(HlopColors.recordingPulse)
                    .opacity(vm.audioCapture.isRecording ? 1 : 0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: vm.audioCapture.isRecording)
            )

            // Error banner
            if let error = vm.audioCapture.lastError {
                InlineErrorCard(
                    message: error,
                    onDismiss: { vm.audioCapture.lastError = nil }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            // STT model download banner
            if !vm.transcriptionService.isModelLoaded && !vm.audioCapture.isRecording {
                HStack(spacing: HlopSpacing.sm) {
                    Image(systemName: "waveform.badge.arrow.down")
                        .font(.system(size: 13))
                        .foregroundStyle(HlopColors.statusSTT)

                    if vm.transcriptionService.isDownloading {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Downloading STT model...")
                                .font(HlopTypography.footnote)
                            ProgressView(value: vm.transcriptionService.downloadProgress)
                                .tint(HlopColors.statusSTT)
                        }
                    } else {
                        Text("STT model needed")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Download") {
                            Task { try? await vm.transcriptionService.loadModel() }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(HlopSpacing.md)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(HlopColors.statusSTT.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            // Vocabulary button
            Button {
                showVocabulary.toggle()
                if showVocabulary {
                    vm.selectedSessionId = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 12))
                    Text("Vocabulary")
                        .font(.system(size: 12))
                    Spacer()
                    if !vm.vocabularyService.terms.isEmpty {
                        Text("\(vm.vocabularyService.terms.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(showVocabulary ? Color.accentColor.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            // Session list
            List(vm.sessionManager.sessions, selection: Binding(
                get: { vm.selectedSessionId },
                set: { id in
                    if let id {
                        showVocabulary = false
                        vm.selectSession(id)
                    }
                }
            )) { session in
                SessionRow(
                    session: session,
                    isProcessing: vm.processingSessionId == session.id,
                    onDelete: { sessionToDelete = session },
                    onProcess: {
                        Task { await vm.processSession(session.id) }
                    },
                    onTranscribe: {
                        Task { await vm.transcribeSession(session.id) }
                    }
                )
                .tag(session.id)
                .contextMenu {
                    Button {
                        Task { await vm.processSession(session.id) }
                    } label: {
                        Label("Process", systemImage: "sparkles")
                    }
                    Button {
                        Task { await vm.transcribeSession(session.id) }
                    } label: {
                        Label("Transcribe", systemImage: "waveform")
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        sessionToDelete = session
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(.ultraThinMaterial)
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
    var onProcess: (() -> Void)?
    var onTranscribe: (() -> Void)?
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
                .accessibilityLabel("Delete recording")
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

                GlassBadge(text: statusLabel, color: statusColor)
            }
        }
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Status Helpers

    private var statusLabel: String {
        if isProcessing { return "..." }
        switch session.status {
        case .recording: return "REC"
        case .recorded: return "NEW"
        case .transcribed: return "STT"
        case .done: return "DONE"
        }
    }

    private var statusColor: Color {
        if isProcessing { return HlopColors.statusProcessing }
        switch session.status {
        case .recording: return HlopColors.recordingBadge
        case .recorded: return HlopColors.statusNew
        case .transcribed: return HlopColors.statusSTT
        case .done: return HlopColors.statusDone
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
