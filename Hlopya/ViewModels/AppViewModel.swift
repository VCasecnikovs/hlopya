import SwiftUI
import Combine

/// Central application state - coordinates all services.
@MainActor
@Observable
final class AppViewModel {
    // Services
    let sessionManager = SessionManager()
    let audioCapture = AudioCaptureService()
    let transcriptionService = TranscriptionService()
    let noteGeneration = NoteGenerationService()
    let obsidianExporter = ObsidianExporter()
    let vocabularyService = VocabularyService()

    // State
    var selectedSessionId: String?
    var isProcessing = false
    var processingSessionId: String?
    var processLog: String = ""
    var processingStages: [ProcessingStage] = []
    var showSettings = false
    var pendingParticipant: String = ""
    var isVocabConfigured = false
    var isConfiguringVocab = false

    // Model lifecycle
    private var modelIdleTimer: Task<Void, Never>?
    private let modelIdleTimeout: TimeInterval = 180 // 3 minutes

    // Nub panel
    private var nubPanel: RecordingNubPanel?

    // Detail data (loaded on selection)
    var detailTranscript: String?
    var detailTranscriptResult: TranscriptResult?
    var detailNotes: MeetingNotes?
    var detailPersonalNotes: String = ""
    var detailMeta: SessionMeta?
    var detailTalkTime: [String: Double] = [:]  // speaker -> percentage

    var selectedSession: Session? {
        sessionManager.sessions.first { $0.id == selectedSessionId }
    }

    // MARK: - Recording

    func startRecording() async {
        var createdSessionId: String?
        do {
            NSLog("[Hlopya] Creating session...")
            let session = try sessionManager.createSession()
            createdSessionId = session.id
            // Save participant info if set
            if !pendingParticipant.isEmpty {
                sessionManager.setParticipant(sessionId: session.id, name: pendingParticipant)
                pendingParticipant = ""
            }
            // Select session immediately so UI shows the new session
            selectSession(session.id)
            NSLog("[Hlopya] Starting recording at %@", session.directoryURL.path)
            try await audioCapture.startRecording(sessionDir: session.directoryURL)
            NSLog("[Hlopya] Recording started OK")
            showNub()
        } catch {
            let msg = error.localizedDescription
            NSLog("[Hlopya] Recording FAILED: %@", msg)
            audioCapture.lastError = msg
            if let id = createdSessionId {
                try? sessionManager.deleteSession(id)
            }
        }
    }

    func stopRecording() async {
        hideNub()
        let sessionId = selectedSessionId
        await audioCapture.stopRecording()
        sessionManager.loadSessions()

        if let id = sessionId {
            selectSession(id)
            // Auto-process if enabled
            if UserDefaults.standard.object(forKey: "autoProcess") == nil || UserDefaults.standard.bool(forKey: "autoProcess") {
                await processSession(id)
            }
        }
    }

    func toggleRecording() async {
        if audioCapture.isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - Session Selection

    private var loadDetailTask: Task<Void, Never>?

    func selectSession(_ id: String) {
        selectedSessionId = id
        // Clear stale data immediately for instant visual feedback
        detailTranscript = nil
        detailTranscriptResult = nil
        detailNotes = nil
        detailPersonalNotes = ""
        detailMeta = nil
        detailTalkTime = [:]

        loadDetailTask?.cancel()
        loadDetailTask = Task {
            await loadSessionDetail(id)
        }
    }

    private func loadSessionDetail(_ id: String) async {
        let dir = Session.recordingsDirectory.appendingPathComponent(id)

        // Heavy file I/O + JSON decoding off main thread
        let loaded = await Task.detached { () -> SessionDetailData in
            let fm = FileManager.default
            let transcriptMd = try? String(contentsOf: dir.appendingPathComponent("transcript.md"), encoding: .utf8)
            let personalNotes = (try? String(contentsOf: dir.appendingPathComponent("personal_notes.md"), encoding: .utf8)) ?? ""

            var notes: MeetingNotes?
            if let data = try? Data(contentsOf: dir.appendingPathComponent("notes.json")) {
                notes = try? JSONDecoder().decode(MeetingNotes.self, from: data)
            }

            var meta: SessionMeta?
            if let data = try? Data(contentsOf: dir.appendingPathComponent("meta.json")) {
                meta = try? JSONDecoder().decode(SessionMeta.self, from: data)
            }

            var transcriptResult: TranscriptResult?
            var talkTime: [String: Double] = [:]
            if let data = try? Data(contentsOf: dir.appendingPathComponent("transcript.json")),
               let transcript = try? JSONDecoder().decode(TranscriptResult.self, from: data) {
                transcriptResult = transcript

                var speakerDurations: [String: Double] = [:]
                for seg in transcript.segments {
                    speakerDurations[seg.speaker, default: 0] += max(seg.end - seg.start, 0)
                }
                let total = speakerDurations.values.reduce(0, +)
                if total > 0 {
                    talkTime = speakerDurations.mapValues { ($0 / total) * 100 }
                } else {
                    let meLen = Double(transcript.meText.count)
                    let themLen = Double(transcript.themText.count)
                    let totalLen = meLen + themLen
                    if totalLen > 0 {
                        talkTime = ["Me": (meLen / totalLen) * 100, "Them": (themLen / totalLen) * 100]
                    }
                }
            }

            return SessionDetailData(
                transcriptMd: transcriptMd,
                notes: notes,
                personalNotes: personalNotes,
                meta: meta,
                transcriptResult: transcriptResult,
                talkTime: talkTime
            )
        }.value

        // Check we're still showing the same session
        guard selectedSessionId == id else { return }

        detailTranscript = loaded.transcriptMd
        detailNotes = loaded.notes
        detailPersonalNotes = loaded.personalNotes
        detailMeta = loaded.meta
        detailTranscriptResult = loaded.transcriptResult
        detailTalkTime = loaded.talkTime
    }

    // MARK: - Processing

    private func updateStage(_ id: String, status: ProcessingStage.Status, detail: String? = nil) {
        guard let idx = processingStages.firstIndex(where: { $0.id == id }) else { return }
        processingStages[idx].status = status
        if let detail { processingStages[idx].detail = detail }
        if case .active = status { processingStages[idx].startedAt = Date() }
        if case .completed = status { processingStages[idx].completedAt = Date() }
        if case .skipped = status { processingStages[idx].completedAt = Date() }
        if case .failed = status { processingStages[idx].completedAt = Date() }
    }

    func processSession(_ sessionId: String) async {
        isProcessing = true
        processingSessionId = sessionId
        processLog = ""
        cancelModelIdleTimer()

        // Build stage list
        var stages: [ProcessingStage] = []
        let needsModel = !transcriptionService.isModelLoaded
        let needsVocab = !vocabularyService.terms.isEmpty && !isVocabConfigured
        let existingTranscript = sessionManager.loadTranscriptJSON(sessionId: sessionId)
        let needsTranscription = existingTranscript?.confidence == nil

        if needsModel {
            stages.append(ProcessingStage(id: "model", title: "Load STT Model", icon: "cpu"))
        }
        if needsVocab {
            stages.append(ProcessingStage(id: "vocab", title: "Configure Vocabulary", icon: "text.book.closed"))
        }
        if needsTranscription {
            stages.append(ProcessingStage(id: "transcribe", title: "Transcribe Audio", icon: "waveform"))
        } else {
            stages.append(ProcessingStage(id: "transcribe", title: "Transcribe Audio", icon: "waveform",
                                          status: .skipped, detail: "Using existing transcript"))
        }
        stages.append(ProcessingStage(id: "notes", title: "Generate Notes", icon: "sparkles"))
        stages.append(ProcessingStage(id: "export", title: "Export to Obsidian", icon: "square.and.arrow.up"))
        processingStages = stages

        do {
            // Load model
            if needsModel {
                updateStage("model", status: .active)
                try await transcriptionService.loadModel()
                updateStage("model", status: .completed, detail: "Parakeet v3 ready")
            }

            // Vocabulary
            if needsVocab {
                updateStage("vocab", status: .active, detail: "\(vocabularyService.terms.count) terms")
                await configureVocabulary()
                updateStage("vocab", status: .completed, detail: "\(vocabularyService.terms.count) terms loaded")
            }

            // Transcribe
            let sessionDir = Session.recordingsDirectory.appendingPathComponent(sessionId)
            let transcript: TranscriptResult
            if let existing = existingTranscript, existing.confidence != nil {
                transcript = existing
            } else {
                updateStage("transcribe", status: .active, detail: "Echo cancellation + ASR...")
                transcript = try await transcriptionService.transcribeMeeting(sessionDir: sessionDir)
                try sessionManager.saveTranscript(transcript, sessionId: sessionId)
                var detail = "\(transcript.numSegments) segments"
                if let conf = transcript.confidence {
                    detail += ", \(String(format: "%.0f", conf * 100))% confidence"
                }
                if let rtfx = transcript.rtfx {
                    detail += ", \(String(format: "%.1f", rtfx))x realtime"
                }
                updateStage("transcribe", status: .completed, detail: detail)
            }

            // Generate notes
            updateStage("notes", status: .active, detail: "Claude is thinking...")
            let personalNotes = sessionManager.loadPersonalNotes(sessionId: sessionId)
            let notes = try await noteGeneration.generateNotes(
                transcript: transcript,
                meta: detailMeta,
                personalNotes: personalNotes.isEmpty ? nil : personalNotes
            )
            try sessionManager.saveNotes(notes, sessionId: sessionId)
            updateStage("notes", status: .completed, detail: notes.title ?? "Notes ready")

            // Export
            updateStage("export", status: .active)
            let obsidianPath = try obsidianExporter.export(notes: notes, sessionId: sessionId)
            updateStage("export", status: .completed, detail: obsidianPath.lastPathComponent)
        } catch {
            // Mark current active stage as failed
            if let activeIdx = processingStages.firstIndex(where: {
                if case .active = $0.status { return true }; return false
            }) {
                processingStages[activeIdx].status = .failed(error.localizedDescription)
                processingStages[activeIdx].completedAt = Date()
            }
            processLog = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
        processingSessionId = nil
        startModelIdleTimer()
        sessionManager.loadSessions()
        if let id = selectedSessionId {
            await loadSessionDetail(id)
        }
    }

    func transcribeSession(_ sessionId: String) async {
        isProcessing = true
        processingSessionId = sessionId
        processLog = ""
        cancelModelIdleTimer()

        var stages: [ProcessingStage] = []
        if !transcriptionService.isModelLoaded {
            stages.append(ProcessingStage(id: "model", title: "Load STT Model", icon: "cpu"))
        }
        stages.append(ProcessingStage(id: "transcribe", title: "Transcribe Audio", icon: "waveform"))
        processingStages = stages

        do {
            if !transcriptionService.isModelLoaded {
                updateStage("model", status: .active)
                try await transcriptionService.loadModel()
                updateStage("model", status: .completed, detail: "Parakeet v3 ready")
            }

            updateStage("transcribe", status: .active, detail: "Echo cancellation + ASR...")
            let sessionDir = Session.recordingsDirectory.appendingPathComponent(sessionId)
            let transcript = try await transcriptionService.transcribeMeeting(sessionDir: sessionDir)
            try sessionManager.saveTranscript(transcript, sessionId: sessionId)
            var detail = "\(transcript.numSegments) segments"
            if let conf = transcript.confidence {
                detail += ", \(String(format: "%.0f", conf * 100))% confidence"
            }
            updateStage("transcribe", status: .completed, detail: detail)
        } catch {
            if let activeIdx = processingStages.firstIndex(where: {
                if case .active = $0.status { return true }; return false
            }) {
                processingStages[activeIdx].status = .failed(error.localizedDescription)
                processingStages[activeIdx].completedAt = Date()
            }
            processLog = "Error: \(error.localizedDescription)"
        }

        isProcessing = false
        processingSessionId = nil
        startModelIdleTimer()
        sessionManager.loadSessions()
        if let id = selectedSessionId {
            await loadSessionDetail(id)
        }
    }

    // MARK: - Model Lifecycle

    /// Start idle timer to unload model after inactivity.
    /// Resets if already running.
    private func startModelIdleTimer() {
        modelIdleTimer?.cancel()
        modelIdleTimer = Task {
            try? await Task.sleep(for: .seconds(modelIdleTimeout))
            guard !Task.isCancelled else { return }
            guard !isProcessing && !audioCapture.isRecording else { return }
            transcriptionService.unloadModel()
            isVocabConfigured = false
            print("[App] Model unloaded after \(Int(modelIdleTimeout))s idle")
        }
    }

    private func cancelModelIdleTimer() {
        modelIdleTimer?.cancel()
        modelIdleTimer = nil
    }

    // MARK: - Vocabulary

    func configureVocabulary() async {
        guard let context = vocabularyService.buildContext() else { return }
        isConfiguringVocab = true
        defer { isConfiguringVocab = false }

        do {
            // Ensure ASR model is loaded first
            if !transcriptionService.isModelLoaded {
                try await transcriptionService.loadModel()
            }

            try await transcriptionService.configureVocabulary(context: context)
            isVocabConfigured = true
            print("[App] Vocabulary configured with \(context.terms.count) terms")
        } catch {
            print("[App] Vocabulary configuration failed: \(error)")
        }
    }

    // MARK: - Auto-save

    private var notesSaveTask: Task<Void, Never>?

    func savePersonalNotes(_ text: String) {
        guard let id = selectedSessionId else { return }
        detailPersonalNotes = text

        notesSaveTask?.cancel()
        notesSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            sessionManager.savePersonalNotes(sessionId: id, text: text)
        }
    }

    func saveEnrichedNotes(_ text: String) {
        guard let id = selectedSessionId else { return }
        sessionManager.saveEnrichedNotes(sessionId: id, text: text)
    }

    // MARK: - Delete

    func deleteSession(_ sessionId: String) {
        do {
            try sessionManager.deleteSession(sessionId)
            if selectedSessionId == sessionId {
                selectedSessionId = nil
                detailTranscript = nil
                detailTranscriptResult = nil
                detailNotes = nil
                detailPersonalNotes = ""
                detailMeta = nil
            }
        } catch {
            print("[App] Delete failed: \(error)")
        }
    }

    // MARK: - Metadata

    func renameSession(_ title: String) {
        guard let id = selectedSessionId else { return }
        sessionManager.renameSession(id, title: title)
    }

    func renameParticipant(oldName: String, newName: String) {
        guard let id = selectedSessionId else { return }
        sessionManager.renameParticipant(sessionId: id, oldName: oldName, newName: newName)
        Task { await loadSessionDetail(id) }
    }

    // MARK: - Nub Panel

    private func showNub() {
        // Defer to next run loop to avoid layout cycle crash during SwiftUI state update
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.audioCapture.isRecording else { return }
            if self.nubPanel == nil {
                self.nubPanel = RecordingNubPanel(viewModel: self)
            }
            self.nubPanel?.orderFront(nil)
        }
    }

    private func hideNub() {
        nubPanel?.close()
        nubPanel = nil
    }
}

/// Data loaded from session files (decoded off main thread)
private struct SessionDetailData: Sendable {
    let transcriptMd: String?
    let notes: MeetingNotes?
    let personalNotes: String
    let meta: SessionMeta?
    let transcriptResult: TranscriptResult?
    let talkTime: [String: Double]
}

/// A single step in the processing pipeline
struct ProcessingStage: Identifiable {
    let id: String
    let title: String
    let icon: String
    var status: Status = .pending
    var detail: String?
    var startedAt: Date?
    var completedAt: Date?

    var duration: TimeInterval? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return end.timeIntervalSince(start)
    }

    enum Status {
        case pending
        case active
        case completed
        case skipped
        case failed(String)
    }
}
