import SwiftUI

/// Detail view: Granola-style layout
/// Top: Notes (My Notes / Enhanced tabs)
/// Bottom: Transcript (always visible, separate scroll)
struct SessionDetailView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var editingTitle = false
    @State private var titleText = ""
    @State private var selectedTab: NoteTab = .myNotes
    @State private var showDebugLog = false
    @State private var searchText = ""
    @State private var titleHovered = false
    @Namespace private var tabAnimation

    enum NoteTab: String {
        case myNotes = "My Notes"
        case enhanced = "Enhanced"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header + tab bar with glass background
            VStack(spacing: 0) {
                headerArea
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Notes tab bar + action buttons
                HStack(spacing: 0) {
                    ForEach(noteTabs, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                                ZStack {
                                    Rectangle()
                                        .fill(.clear)
                                        .frame(height: 2)
                                    if selectedTab == tab {
                                        Rectangle()
                                            .fill(Color.accentColor)
                                            .frame(height: 2)
                                            .matchedGeometryEffect(id: "tabIndicator", in: tabAnimation)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    actionButtons
                }
                .padding(.horizontal, 20)

                Divider()
            }
            .background(.ultraThinMaterial)

            // Split: notes on top, transcript on bottom
            if vm.detailTranscript != nil {
                VSplitView {
                    // Notes area
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            notesContent
                        }
                        .padding(24)
                    }
                    .frame(minHeight: 150)

                    // Transcript area
                    VStack(spacing: 0) {
                        // Transcript header
                        HStack {
                            SectionHeader(title: "Transcript", icon: "waveform")
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                        Divider()

                        // Search in transcript
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.tertiary)
                            TextField("Search transcript...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(HlopTypography.body)
                        }
                        .padding(.horizontal, HlopSpacing.lg)
                        .padding(.vertical, HlopSpacing.sm)

                        Divider()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                transcriptContent
                            }
                            .padding(16)
                        }
                    }
                    .frame(minHeight: 120)
                }
            } else {
                // No transcript yet - just notes
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        notesContent
                    }
                    .padding(24)
                }
            }

            // Debug log
            if !vm.processLog.isEmpty {
                debugLogBar
            }
        }
        .onChange(of: vm.selectedSessionId) { _, newId in
            if let id = newId, let session = vm.sessionManager.sessions.first(where: { $0.id == id }) {
                titleText = session.displayTitle
            }
            if !noteTabs.contains(selectedTab) {
                selectedTab = .myNotes
            }
        }
        .onAppear {
            if let session = vm.selectedSession {
                titleText = session.displayTitle
            }
        }
    }

    // MARK: - Note Tabs

    private var noteTabs: [NoteTab] {
        var tabs: [NoteTab] = [.myNotes]
        if let notes = vm.detailNotes, let enriched = notes.enrichedNotes, !enriched.isEmpty {
            tabs.append(.enhanced)
        }
        return tabs
    }

    // MARK: - Notes Content (switches by tab)

    @ViewBuilder
    private var notesContent: some View {
        switch selectedTab {
        case .myNotes:
            personalNotesEditor
        case .enhanced:
            enhancedContent
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editingTitle {
                TextField("Title", text: $titleText, onCommit: {
                    vm.renameSession(titleText)
                    editingTitle = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .bold))
                .onExitCommand { editingTitle = false }
            } else {
                HStack(spacing: 6) {
                    Text(vm.selectedSession?.displayTitle ?? "")
                        .font(.system(size: 20, weight: .bold))
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .opacity(titleHovered ? 1 : 0)
                }
                .onHover { titleHovered = $0 }
                .onTapGesture { editingTitle = true }
                .accessibilityLabel("Edit title")
                .accessibilityHint("Click to edit meeting title")
            }

            if let session = vm.selectedSession {
                HStack(spacing: 12) {
                    Label(Session.fullDateFormatter.string(from: session.date), systemImage: "calendar")

                    if session.duration > 0 {
                        Label(formatDuration(session.duration), systemImage: "clock")
                    }

                    if let confidence = vm.detailTranscriptResult?.confidence {
                        Label("\(Int(confidence * 100))%", systemImage: "waveform.badge.magnifyingglass")
                            .foregroundStyle(confidence < 0.5 ? HlopColors.statusWarning : .secondary)
                    }

                    if let rtfx = vm.detailTranscriptResult?.rtfx {
                        Label("\(String(format: "%.1f", rtfx))x", systemImage: "bolt")
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
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                if !vm.detailTalkTime.isEmpty {
                    talkTimeBar
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if vm.audioCapture.isRecording {
                // During recording - no action buttons, just chill
            } else if vm.isProcessing {
                ProcessingProgress(
                    stage: vm.processLog.isEmpty
                        ? "Processing..."
                        : String(vm.processLog.split(separator: "\n").last ?? "Processing...")
                )
            } else {
                if vm.selectedSession?.hasNotes != true {
                    Button {
                        if let id = vm.selectedSessionId {
                            Task { await vm.processSession(id) }
                        }
                    } label: {
                        Label("Process", systemImage: "sparkles")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Process session")
                } else if vm.selectedSession?.hasTranscript != true {
                    Button {
                        if let id = vm.selectedSessionId {
                            Task { await vm.transcribeSession(id) }
                        }
                    } label: {
                        Label("Transcribe", systemImage: "waveform")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Transcribe session")
                }
            }
        }
    }

    // MARK: - Enhanced Content

    private var enhancedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let notes = vm.detailNotes, let enriched = notes.enrichedNotes, !enriched.isEmpty {
                NotesView(markdown: enriched) { newText in
                    vm.saveEnrichedNotes(newText)
                }

                if let items = notes.actionItems, !items.isEmpty {
                    actionItemsSection(items)
                }

                if let decisions = notes.decisions, !decisions.isEmpty {
                    decisionsSection(decisions)
                }
            }
        }
    }

    // MARK: - Action Items

    private func actionItemsSection(_ items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Action Items", icon: "checklist")
                .padding(.top, 8)

            ForEach(items) { item in
                ActionItemRow(item: item)
            }
        }
    }

    // MARK: - Decisions

    private func decisionsSection(_ decisions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Decisions", icon: "checkmark.seal")
                .padding(.top, 8)

            ForEach(decisions, id: \.self) { d in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(HlopColors.statusDone)
                    Text(d)
                        .font(.system(size: 14))
                }
            }
        }
    }

    // MARK: - Personal Notes Editor

    private var personalNotesEditor: some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: 8) {
            Text("Write notes during the meeting. They'll be enhanced with transcript context after processing.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)

            TextEditor(text: Binding(
                get: { vm.detailPersonalNotes },
                set: { vm.savePersonalNotes($0) }
            ))
            .font(.system(size: 14))
            .frame(minHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Transcript Content

    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let transcript = vm.detailTranscript {
                TranscriptView(
                    markdown: transcript,
                    participantNames: vm.selectedSession?.participantNames ?? [:],
                    segments: vm.detailTranscriptResult?.segments ?? []
                )
            }
        }
    }

    // MARK: - Debug Log

    private var debugLogBar: some View {
        VStack(spacing: 0) {
            Divider()
            DisclosureGroup("Processing Log", isExpanded: $showDebugLog) {
                ScrollView {
                    Text(vm.processLog)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Talk-Time Bar

    private var talkTimeBar: some View {
        let names = vm.selectedSession?.participantNames ?? [:]
        let sorted = vm.detailTalkTime.sorted { $0.value > $1.value }

        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(sorted, id: \.key) { speaker, pct in
                        let isMe = speaker == "Me" || speaker == "Vadim"
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isMe ? HlopColors.statusMe : HlopColors.statusThem)
                            .frame(width: max(geo.size.width * (pct / 100), 4))
                    }
                }
            }
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))

            HStack(spacing: 12) {
                ForEach(sorted, id: \.key) { speaker, pct in
                    let isMe = speaker == "Me" || speaker == "Vadim"
                    let displayName = names[speaker] ?? speaker
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isMe ? HlopColors.statusMe : HlopColors.statusThem)
                            .frame(width: 6, height: 6)
                        Text("\(displayName) \(Int(pct))%")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        if m >= 60 {
            return "\(m / 60)h \(m % 60)m"
        }
        return "\(m)m \(s)s"
    }
}

// MARK: - Supporting Views

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
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onExitCommand { isEditing = false }
        } else {
            Text(name)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let owner = item.owner {
                        Text(owner)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(item.task)
                        .font(.system(size: 13))
                }
                if let deadline = item.deadline {
                    Text("Due: \(deadline)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
