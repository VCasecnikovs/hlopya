import Foundation

/// Manages recording sessions stored in ~/recordings/{YYYY-MM-DD_HH-MM-SS}/
/// Handles CRUD operations, file I/O, and session metadata.
@MainActor
@Observable
final class SessionManager {
    var sessions: [Session] = []

    private let recordingsDir: URL

    init() {
        self.recordingsDir = Session.recordingsDirectory
        migrateMetaIfNeeded()
        loadSessions()
    }

    /// One-time migration: backfill meta.json with duration/title/participants/status
    /// from transcript.json and notes.json, so loadSessions() never needs heavy files.
    private func migrateMetaIfNeeded() {
        let fm = FileManager.default
        let marker = recordingsDir.appendingPathComponent(".meta_migrated")
        guard !fm.fileExists(atPath: marker.path) else { return }

        guard let contents = try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let dir = url

            var updates: [String: Any] = [:]

            // Read duration from transcript.json if meta doesn't have it
            let meta = loadMeta(sessionDir: dir)
            if meta?.duration == nil || meta?.duration == 0 {
                let transcriptPath = dir.appendingPathComponent("transcript.json")
                if let data = try? Data(contentsOf: transcriptPath) {
                    struct LegacyMeta: Decodable {
                        let durationSeconds: Double
                        enum CodingKeys: String, CodingKey { case durationSeconds = "duration_seconds" }
                    }
                    if let tm = try? JSONDecoder().decode(LegacyMeta.self, from: data) {
                        updates["duration"] = tm.durationSeconds
                    }
                }
            }

            // Read title/participants from notes.json if meta doesn't have them
            if meta?.title == nil || meta?.participants == nil {
                let notesPath = dir.appendingPathComponent("notes.json")
                if let data = try? Data(contentsOf: notesPath) {
                    struct LegacyNotes: Decodable {
                        let title: String?
                        let participants: [String]?
                    }
                    if let nm = try? JSONDecoder().decode(LegacyNotes.self, from: data) {
                        if meta?.title == nil, let title = nm.title { updates["title"] = title }
                        if meta?.participants == nil, let p = nm.participants { updates["participants"] = p }
                    }
                }
            }

            // Set status
            if meta?.status == nil {
                let hasNotes = fm.fileExists(atPath: dir.appendingPathComponent("notes.json").path)
                let hasTranscript = fm.fileExists(atPath: dir.appendingPathComponent("transcript.json").path)
                if hasNotes { updates["status"] = "done" }
                else if hasTranscript { updates["status"] = "transcribed" }
                else { updates["status"] = "recorded" }
            }

            if !updates.isEmpty {
                saveMeta(sessionDir: dir, updates: updates)
            }
        }

        // Mark migration complete
        fm.createFile(atPath: marker.path, contents: nil)
        print("[SessionManager] Meta migration complete")
    }

    // MARK: - Session Lifecycle

    /// Create a new recording session directory
    func createSession() throws -> Session {
        let id = Session.newSessionId()
        let dir = recordingsDir.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let session = Session(
            id: id, title: nil, participants: [], participantNames: [:],
            duration: 0, status: .recording,
            hasMic: false, hasSystem: false,
            hasTranscript: false, hasNotes: false, hasPersonalNotes: false
        )

        sessions.insert(session, at: 0)
        return session
    }

    /// Refresh sessions from disk.
    /// Only reads meta.json (tiny) + fileExists checks per session.
    /// Heavy files (transcript.json, notes.json) are NOT read here.
    func loadSessions() {
        guard FileManager.default.fileExists(atPath: recordingsDir.path) else {
            sessions = []
            return
        }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            sessions = []
            return
        }

        sessions = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { url -> Session in
                let id = url.lastPathComponent
                let dir = url

                let hasMic = fm.fileExists(atPath: dir.appendingPathComponent("mic.wav").path)
                let hasSys = fm.fileExists(atPath: dir.appendingPathComponent("system.wav").path)
                let hasTranscript = fm.fileExists(atPath: dir.appendingPathComponent("transcript.json").path)
                let hasNotes = fm.fileExists(atPath: dir.appendingPathComponent("notes.json").path)
                let hasPersonalNotes = fm.fileExists(atPath: dir.appendingPathComponent("personal_notes.md").path)

                // All session list data comes from meta.json (~100 bytes)
                let meta = loadMeta(sessionDir: dir)

                let status: SessionStatus
                if let s = meta?.status, let parsed = SessionStatus(rawValue: s) {
                    status = parsed
                } else if hasNotes { status = .done }
                else if hasTranscript { status = .transcribed }
                else { status = .recorded }

                return Session(
                    id: id,
                    title: meta?.title,
                    participants: meta?.participants ?? [],
                    participantNames: meta?.participantNames ?? [:],
                    duration: meta?.duration ?? 0,
                    status: status,
                    hasMic: hasMic, hasSystem: hasSys,
                    hasTranscript: hasTranscript, hasNotes: hasNotes,
                    hasPersonalNotes: hasPersonalNotes
                )
            }
            .sorted { $0.id > $1.id }
    }

    // MARK: - Session Data

    func loadTranscriptJSON(sessionId: String) -> TranscriptResult? {
        let path = recordingsDir.appendingPathComponent(sessionId).appendingPathComponent("transcript.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(TranscriptResult.self, from: data)
    }

    func loadTranscriptMarkdown(sessionId: String) -> String? {
        let path = recordingsDir.appendingPathComponent(sessionId).appendingPathComponent("transcript.md")
        return try? String(contentsOf: path, encoding: .utf8)
    }

    func loadNotes(sessionId: String) -> MeetingNotes? {
        let path = recordingsDir.appendingPathComponent(sessionId).appendingPathComponent("notes.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(MeetingNotes.self, from: data)
    }

    func loadPersonalNotes(sessionId: String) -> String {
        let path = recordingsDir.appendingPathComponent(sessionId).appendingPathComponent("personal_notes.md")
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    // MARK: - Save Operations

    func savePersonalNotes(sessionId: String, text: String) {
        let dir = recordingsDir.appendingPathComponent(sessionId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("personal_notes.md")
        try? text.write(to: path, atomically: true, encoding: .utf8)
    }

    func saveTranscript(_ result: TranscriptResult, sessionId: String) throws {
        let dir = recordingsDir.appendingPathComponent(sessionId)

        // JSON
        let jsonPath = dir.appendingPathComponent("transcript.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(result)
        try data.write(to: jsonPath)

        // Markdown
        let mdPath = dir.appendingPathComponent("transcript.md")
        var md = "# Meeting Transcript\n\n"
        md += "- Model: \(result.modelUsed)\n"
        md += "- Segments: \(result.numSegments)\n"
        if result.durationSeconds > 0 {
            let m = Int(result.durationSeconds) / 60
            let s = Int(result.durationSeconds) % 60
            md += "- Duration: \(m)m \(s)s\n"
        }
        md += "- Processing time: \(String(format: "%.1f", result.processingTime))s\n"
        if let rtfx = result.rtfx {
            md += "- Speed: \(String(format: "%.1f", rtfx))x realtime\n"
        }
        if let confidence = result.confidence {
            md += "- Confidence: \(String(format: "%.0f", confidence * 100))%\n"
        }
        md += "\n---\n\n"
        md += result.fullText
        try md.write(to: mdPath, atomically: true, encoding: .utf8)

        // Persist duration + status into meta.json for fast session list loading
        saveMeta(sessionDir: dir, updates: [
            "duration": result.durationSeconds,
            "status": "transcribed"
        ])

        // Update session in list
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].hasTranscript = true
            sessions[idx].duration = result.durationSeconds
            if sessions[idx].status == .recorded {
                sessions[idx].status = .transcribed
            }
        }
    }

    func saveNotes(_ notes: MeetingNotes, sessionId: String) throws {
        let dir = recordingsDir.appendingPathComponent(sessionId)
        let path = dir.appendingPathComponent("notes.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(notes)
        try data.write(to: path)

        // Persist title + participants + status into meta.json for fast session list loading
        var metaUpdates: [String: Any] = ["status": "done"]
        if let title = notes.title { metaUpdates["title"] = title }
        if let participants = notes.participants { metaUpdates["participants"] = participants }
        saveMeta(sessionDir: dir, updates: metaUpdates)

        // Update session
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].hasNotes = true
            sessions[idx].status = .done
            if sessions[idx].title == nil {
                sessions[idx].title = notes.title
            }
            sessions[idx].participants = notes.participants ?? []
        }
    }

    func saveEnrichedNotes(sessionId: String, text: String) {
        let path = recordingsDir.appendingPathComponent(sessionId).appendingPathComponent("notes.json")
        guard var notes = loadNotes(sessionId: sessionId) else { return }
        notes.enrichedNotes = text
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: path)
        }
    }

    // MARK: - Delete

    func deleteSession(_ sessionId: String) throws {
        let dir = recordingsDir.appendingPathComponent(sessionId)
        try FileManager.default.removeItem(at: dir)
        sessions.removeAll { $0.id == sessionId }
    }

    // MARK: - Participants

    func setParticipant(sessionId: String, name: String) {
        let dir = recordingsDir.appendingPathComponent(sessionId)
        saveMeta(sessionDir: dir, updates: [
            "participant_names": ["Them": name],
            "meeting_with": name
        ])
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].participantNames = ["Them": name]
        }
    }

    // MARK: - Metadata

    func renameSession(_ sessionId: String, title: String) {
        let dir = recordingsDir.appendingPathComponent(sessionId)
        saveMeta(sessionDir: dir, updates: ["title": title])
        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].title = title
        }
    }

    func renameParticipant(sessionId: String, oldName: String, newName: String) {
        let dir = recordingsDir.appendingPathComponent(sessionId)

        // Update notes.json
        if var notes = loadNotes(sessionId: sessionId) {
            notes.participants = notes.participants?.map { $0 == oldName ? newName : $0 }
            if let enriched = notes.enrichedNotes {
                notes.enrichedNotes = enriched.replacingOccurrences(of: oldName, with: newName)
            }
            notes.actionItems = notes.actionItems?.map { item in
                var item = item
                if item.owner == oldName { item.owner = newName }
                return item
            }
            try? saveNotes(notes, sessionId: sessionId)
        }

        // Save name mapping in meta
        var nameMap = loadMeta(sessionDir: dir)?.participantNames ?? [:]
        if oldName.lowercased().hasPrefix("them") || nameMap["Them"] == oldName {
            nameMap["Them"] = newName
        } else if oldName.lowercased().hasPrefix("me") || oldName.lowercased().hasPrefix("vadim") || nameMap["Me"] == oldName {
            nameMap["Me"] = newName
        }
        saveMeta(sessionDir: dir, updates: ["participant_names": nameMap])

        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].participantNames = nameMap
        }
    }

    // MARK: - Meta helpers

    private func loadMeta(sessionDir: URL) -> SessionMeta? {
        let path = sessionDir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(SessionMeta.self, from: data)
    }

    private func saveMeta(sessionDir: URL, updates: [String: Any]) {
        let path = sessionDir.appendingPathComponent("meta.json")

        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: path),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        }

        for (key, value) in updates {
            dict[key] = value
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: path)
        }
    }
}
