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
    var showSettings = false
    var pendingParticipant: String = ""
    var isVocabConfigured = false
    var isConfiguringVocab = false

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
            NSLog("[Hlopya] Starting recording at %@", session.directoryURL.path)
            try await audioCapture.startRecording(sessionDir: session.directoryURL)
            selectSession(session.id)
            NSLog("[Hlopya] Recording started OK")
            showNub()
        } catch {
            let msg = error.localizedDescription
            NSLog("[Hlopya] Recording FAILED: %@", msg)
            audioCapture.lastError = msg
            // Clean up the failed session we just created
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

    func selectSession(_ id: String) {
        selectedSessionId = id
        loadSessionDetail(id)
    }

    private func loadSessionDetail(_ id: String) {
        detailTranscript = sessionManager.loadTranscriptMarkdown(sessionId: id)
        detailNotes = sessionManager.loadNotes(sessionId: id)
        detailPersonalNotes = sessionManager.loadPersonalNotes(sessionId: id)

        let dir = Session.recordingsDirectory.appendingPathComponent(id)
        let metaPath = dir.appendingPathComponent("meta.json")
        if let data = try? Data(contentsOf: metaPath) {
            detailMeta = try? JSONDecoder().decode(SessionMeta.self, from: data)
        } else {
            detailMeta = nil
        }

        // Load transcript JSON for talk-time and confidence data
        let transcriptPath = dir.appendingPathComponent("transcript.json")
        if let data = try? Data(contentsOf: transcriptPath),
           let transcript = try? JSONDecoder().decode(TranscriptResult.self, from: data) {
            detailTranscriptResult = transcript
            var speakerDurations: [String: Double] = [:]
            for seg in transcript.segments {
                let dur = max(seg.end - seg.start, 0)
                speakerDurations[seg.speaker, default: 0] += dur
            }
            let total = speakerDurations.values.reduce(0, +)
            if total > 0 {
                detailTalkTime = speakerDurations.mapValues { ($0 / total) * 100 }
            } else {
                // Fallback: count by text length
                let meLen = Double(transcript.meText.count)
                let themLen = Double(transcript.themText.count)
                let totalLen = meLen + themLen
                if totalLen > 0 {
                    detailTalkTime = ["Me": (meLen / totalLen) * 100, "Them": (themLen / totalLen) * 100]
                } else {
                    detailTalkTime = [:]
                }
            }
        } else {
            detailTranscriptResult = nil
            detailTalkTime = [:]
        }
    }

    // MARK: - Processing

    func processSession(_ sessionId: String) async {
        isProcessing = true
        processingSessionId = sessionId
        processLog = "Starting transcription...\n"

        do {
            // Ensure model is loaded
            if !transcriptionService.isModelLoaded {
                processLog += "Loading STT model...\n"
                try await transcriptionService.loadModel()
                processLog += "Model loaded.\n"
            }

            // Configure vocabulary if available
            if !vocabularyService.terms.isEmpty && !isVocabConfigured {
                processLog += "Configuring vocabulary (\(vocabularyService.terms.count) terms)...\n"
                await configureVocabulary()
            }

            // Transcribe (skip if already has transcript)
            let sessionDir = Session.recordingsDirectory.appendingPathComponent(sessionId)
            let transcript: TranscriptResult
            let existingTranscript = sessionManager.loadTranscriptJSON(sessionId: sessionId)
            if let existing = existingTranscript {
                transcript = existing
                processLog += "Using existing transcript (\(transcript.numSegments) segments)\n"
            } else {
                processLog += "Transcribing audio...\n"
                transcript = try await transcriptionService.transcribeMeeting(sessionDir: sessionDir)
                try sessionManager.saveTranscript(transcript, sessionId: sessionId)
                processLog += "Transcription done: \(transcript.numSegments) segments"
                if let conf = transcript.confidence {
                    processLog += ", confidence: \(String(format: "%.0f", conf * 100))%"
                }
                if let rtfx = transcript.rtfx {
                    processLog += ", speed: \(String(format: "%.1f", rtfx))x"
                }
                processLog += "\n"
            }

            // Generate notes
            processLog += "Generating notes with Claude...\n"
            let personalNotes = sessionManager.loadPersonalNotes(sessionId: sessionId)
            let notes = try await noteGeneration.generateNotes(
                transcript: transcript,
                meta: detailMeta,
                personalNotes: personalNotes.isEmpty ? nil : personalNotes
            )
            try sessionManager.saveNotes(notes, sessionId: sessionId)
            processLog += "Notes generated.\n"

            // Export to Obsidian
            let obsidianPath = try obsidianExporter.export(notes: notes, sessionId: sessionId)
            processLog += "Exported to Obsidian: \(obsidianPath.lastPathComponent)\n"

            processLog += "\nDone!\n"
        } catch {
            processLog += "\nError: \(error.localizedDescription)\n"
        }

        isProcessing = false
        processingSessionId = nil
        sessionManager.loadSessions()
        if let id = selectedSessionId {
            loadSessionDetail(id)
        }
    }

    func transcribeSession(_ sessionId: String) async {
        isProcessing = true
        processingSessionId = sessionId
        processLog = "Starting transcription...\n"

        do {
            if !transcriptionService.isModelLoaded {
                processLog += "Loading STT model...\n"
                try await transcriptionService.loadModel()
            }

            let sessionDir = Session.recordingsDirectory.appendingPathComponent(sessionId)
            let transcript = try await transcriptionService.transcribeMeeting(sessionDir: sessionDir)
            try sessionManager.saveTranscript(transcript, sessionId: sessionId)
            processLog += "Done: \(transcript.numSegments) segments\n"
        } catch {
            processLog += "Error: \(error.localizedDescription)\n"
        }

        isProcessing = false
        processingSessionId = nil
        sessionManager.loadSessions()
        if let id = selectedSessionId {
            loadSessionDetail(id)
        }
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
        loadSessionDetail(id)
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
