import SwiftUI

/// Detail view: metadata bar, enriched notes, transcript, personal notes, action items
struct SessionDetailView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var editingTitle = false
    @State private var titleText = ""
    @State private var showDebugLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title - large and editable
                titleView
                    .padding(.bottom, 4)

                metadataBar
                actionButtons

                if let notes = vm.detailNotes {
                    notesSection(notes)
                }

                personalNotesSection

                if let transcript = vm.detailTranscript {
                    transcriptSection(transcript)
                }

                if !vm.processLog.isEmpty {
                    debugLogSection
                }

                // Empty state
                if vm.detailTranscript == nil && vm.detailNotes == nil && vm.detailPersonalNotes.isEmpty {
                    Text("Recording available. Click Transcribe or Process to generate transcript and notes.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding(24)
        }
        .onChange(of: vm.selectedSessionId) { _, newId in
            if let id = newId, let session = vm.sessionManager.sessions.first(where: { $0.id == id }) {
                titleText = session.displayTitle
            }
        }
        .onAppear {
            if let session = vm.selectedSession {
                titleText = session.displayTitle
            }
        }
    }

    // MARK: - Title

    private var titleView: some View {
        Group {
            if editingTitle {
                TextField("Title", text: $titleText, onCommit: {
                    vm.renameSession(titleText)
                    editingTitle = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .onExitCommand { editingTitle = false }
            } else {
                Text(vm.selectedSession?.displayTitle ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .onTapGesture { editingTitle = true }
            }
        }
    }

    // MARK: - Metadata Bar

    private var metadataBar: some View {
        HStack(spacing: 16) {
            if let session = vm.selectedSession {
                Label(Session.fullDateFormatter.string(from: session.date), systemImage: "calendar")

                if session.duration > 0 {
                    Label(formatDuration(session.duration), systemImage: "clock")
                }

                if !session.participants.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                        ForEach(session.participants, id: \.self) { p in
                            ParticipantChip(name: p) { newName in
                                vm.renameParticipant(oldName: p, newName: newName)
                            }
                        }
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if vm.selectedSession?.hasTranscript != true {
                Button("Transcribe") {
                    if let id = vm.selectedSessionId {
                        Task { await vm.transcribeSession(id) }
                    }
                }
                .disabled(vm.isProcessing)
            }

            if vm.selectedSession?.hasNotes != true {
                Button("Process") {
                    if let id = vm.selectedSessionId {
                        Task { await vm.processSession(id) }
                    }
                }
                .disabled(vm.isProcessing)
            }

            if vm.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("Processing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private func notesSection(_ notes: MeetingNotes) -> some View {
        if let enriched = notes.enrichedNotes, !enriched.isEmpty {
            SectionHeader(title: "Meeting Notes")
            NotesView(markdown: enriched) { newText in
                vm.saveEnrichedNotes(newText)
            }
        }

        if let summary = notes.summary, !summary.isEmpty {
            SectionHeader(title: "Summary")
            Text(summary)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }

        if let items = notes.actionItems, !items.isEmpty {
            SectionHeader(title: "Action Items")
            ForEach(items) { item in
                ActionItemRow(item: item)
            }
        }

        if let decisions = notes.decisions, !decisions.isEmpty {
            SectionHeader(title: "Decisions")
            ForEach(decisions, id: \.self) { d in
                HStack(alignment: .top) {
                    Text("-")
                    Text(d)
                }
                .font(.body)
            }
        }
    }

    // MARK: - Personal Notes

    private var personalNotesSection: some View {
        VStack(alignment: .leading) {
            let hasNotes = vm.detailNotes != nil

            if hasNotes {
                DisclosureGroup("Personal Notes") {
                    personalNotesEditor
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                SectionHeader(title: "Personal Notes")
                personalNotesEditor
            }
        }
    }

    private var personalNotesEditor: some View {
        @Bindable var vm = vm
        return TextEditor(text: Binding(
            get: { vm.detailPersonalNotes },
            set: { vm.savePersonalNotes($0) }
        ))
        .font(.body)
        .frame(minHeight: vm.detailNotes != nil ? 120 : 300)
        .scrollContentBackground(.hidden)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptSection(_ transcript: String) -> some View {
        SectionHeader(title: "Transcript")
        TranscriptView(
            markdown: transcript,
            participantNames: vm.selectedSession?.participantNames ?? [:]
        )
    }

    // MARK: - Debug Log

    private var debugLogSection: some View {
        DisclosureGroup("Debug Log", isExpanded: $showDebugLog) {
            ScrollView {
                Text(vm.processLog)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        if m >= 60 {
            let h = m / 60
            let rm = m % 60
            return "\(h)h \(rm)m"
        }
        return "\(m)m \(s)s"
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1)
    }
}

struct ParticipantChip: View {
    let name: String
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        if isEditing {
            TextField("Name", text: $editText, onCommit: {
                if !editText.isEmpty && editText != name {
                    onRename(editText)
                }
                isEditing = false
            })
            .textFieldStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onExitCommand { isEditing = false }
        } else {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onTapGesture {
                    editText = name
                    isEditing = true
                }
        }
    }
}

struct ActionItemRow: View {
    let item: ActionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.owner ?? "?")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                Text(item.task)
                    .font(.callout)
            }
            if let deadline = item.deadline {
                Text("Due: \(deadline)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
