import Foundation

/// Generates structured meeting notes using Claude CLI.
/// Port of noter.py - same prompt template, same JSON schema.
final class NoteGenerationService {

    var model: String {
        UserDefaults.standard.string(forKey: "claudeModel").flatMap { $0.isEmpty ? nil : $0 } ?? "sonnet"
    }

    /// Generate notes from a transcript using `claude -p`
    func generateNotes(
        transcript: TranscriptResult,
        meta: SessionMeta?,
        personalNotes: String?
    ) async throws -> MeetingNotes {
        let prompt = buildPrompt(transcript: transcript, meta: meta, personalNotes: personalNotes)

        // Find claude CLI
        let claudePath = Self.findClaudeCLI()

        print("[NoteGeneration] Generating notes with claude -p (model: \(model))...")

        // Run claude -p
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = ["-p", "--model", model, "--output-format", "text"]

        // Fix environment for GUI-launched app:
        // - Remove CLAUDECODE to avoid nested session error
        // - Ensure PATH includes Homebrew/local dirs so `env node` shebang works
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin",
                          "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let missing = extraPaths.filter { !currentPath.contains($0) }
        if !missing.isEmpty {
            env["PATH"] = currentPath + ":" + missing.joined(separator: ":")
        }
        process.environment = env

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Write prompt to stdin
        let promptData = prompt.data(using: .utf8)!
        inputPipe.fileHandleForWriting.write(promptData)
        inputPipe.fileHandleForWriting.closeFile()

        // Wait with timeout
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global().async {
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    continuation.resume(throwing: NoteGenerationError.claudeFailed(Int(process.terminationStatus), stderr))
                    return
                }

                let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: stdout)
            }
        }

        return parseResponse(result, transcript: transcript)
    }

    static func findClaudeCLI() -> String {
        let paths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/claude",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.claude/bin/claude",
        ]

        for p in paths {
            if FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }

        // Try which
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !path.isEmpty { return path }

        return "claude"  // Hope it's in PATH
    }

    private func parseResponse(_ text: String, transcript: TranscriptResult) -> MeetingNotes {
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract JSON from markdown code block if present
        if jsonText.contains("```json") {
            jsonText = String(jsonText.split(separator: "```json", maxSplits: 1).last?
                .split(separator: "```", maxSplits: 1).first ?? "")
        } else if jsonText.contains("```") {
            jsonText = String(jsonText.split(separator: "```", maxSplits: 1).last?
                .split(separator: "```", maxSplits: 1).first ?? "")
        }

        let decoder = JSONDecoder()
        var notes: MeetingNotes
        if let data = jsonText.data(using: .utf8),
           let parsed = try? decoder.decode(MeetingNotes.self, from: data) {
            notes = parsed
        } else {
            print("[NoteGeneration] Warning: Could not parse JSON response")
            notes = MeetingNotes(rawText: text, parseError: true)
        }

        notes.modelUsed = model
        notes.transcriptStats = TranscriptStats(
            segments: transcript.numSegments,
            duration: transcript.durationSeconds,
            sttModel: transcript.modelUsed
        )

        return notes
    }

    // MARK: - Prompt (verbatim from noter.py)

    private func buildPrompt(
        transcript: TranscriptResult,
        meta: SessionMeta?,
        personalNotes: String?
    ) -> String {
        let personalSection: String
        if let pn = personalNotes, !pn.isEmpty {
            personalSection = """

            ## User's Personal Notes (CRITICAL - these form the backbone of enriched_notes)

            Each line below was written by the user during the meeting. Preserve ALL of them as **bold** lines in enriched_notes, in order. Enrich each with context from the transcript.

            ```
            \(pn)
            ```
            """
        } else {
            personalSection = """

            ## User's Personal Notes

            (No personal notes were taken. Generate enriched_notes purely from the transcript.)
            """
        }

        let dateStr = meta?.title != nil ? "" : DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)

        let userName = UserDefaults.standard.string(forKey: "userName").flatMap { $0.isEmpty ? nil : $0 }
        let meName = userName.map { "Me (\($0))" } ?? "Me"

        let otherParticipants: String
        if let meetingWith = meta?.meetingWith, !meetingWith.isEmpty {
            let names = meetingWith.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            otherParticipants = names.joined(separator: ", ")
        } else if let themName = meta?.participantNames?["Them"], !themName.isEmpty {
            otherParticipants = themName
        } else {
            otherParticipants = "Them"
        }

        let participantNote = otherParticipants.contains(",")
            ? "\nNote: The transcript only has \"Me\" and \"Them\" audio channels. \"Them\" includes multiple participants (\(otherParticipants)). Attribute utterances to the correct person based on context when possible."
            : ""

        return """
        \(Self.systemPrompt)

        ## Meeting Info

        Date: \(dateStr)
        Title: \(meta?.title ?? "Meeting")
        Known participants: \(meName), \(otherParticipants)
        \(participantNote)
        \(personalSection)
        ## Transcript

        \(transcript.fullText)
        """
    }

    static let systemPrompt = """
    You are a meeting notes assistant. You receive a diarized transcript and the user's personal notes taken during the meeting.

    Your job: produce structured meeting notes that INTEGRATE the user's personal notes as the backbone. The user's original notes should be preserved verbatim and highlighted, with AI-generated context enriching around them.

    ## Output Format (JSON)

    Return ONLY a valid JSON object (no markdown fences, no extra text) with these fields:

    {
      "title": "Short meeting title",
      "date": "YYYY-MM-DD",
      "participants": ["Name 1", "Name 2"],
      "summary": "2-3 sentence summary of what was discussed and decided",
      "enriched_notes": "Markdown string - see rules below",
      "topics": [
        {"topic": "Topic name", "details": "Key points discussed"}
      ],
      "decisions": ["Decision 1", "Decision 2"],
      "action_items": [
        {
          "owner": "Person name",
          "task": "What needs to be done",
          "deadline": "YYYY-MM-DD or null",
          "context": "Why this matters, full context for the task"
        }
      ],
      "insights": ["Key insight 1", "Key insight 2"],
      "follow_ups": ["Suggested follow-up 1", "Suggested follow-up 2"]
    }

    ## enriched_notes Rules (CRITICAL - this is the main output)

    The enriched_notes field is a markdown string that merges the user's notes with transcript context:

    1. Each line from the user's personal notes becomes a **bold** line (wrapped in **)
    2. Below each user note, add 1-3 lines of AI context from the transcript - details, numbers, quotes, who said what
    3. If the user wrote nothing, create the enriched notes purely from the transcript
    4. Group related notes under topic headers (## headers)
    5. Add topics from the transcript that the user DIDN'T note (mark these sections without bold)
    6. Preserve the user's note ordering - don't rearrange

    ## Other Rules
    - Extract EVERY actionable commitment from the meeting
    - Make action items self-contained (enough context to act without re-reading transcript)
    - Note numbers: pricing, volumes, timelines, team sizes
    - Note relationship dynamics and who knows whom
    - Flag any deadlines or time-sensitive items
    - Preserve important Russian quotes verbatim
    - Language: English for notes, Russian only for direct quotes
    - Return ONLY the JSON object, nothing else
    """
}

enum NoteGenerationError: LocalizedError {
    case claudeFailed(Int, String)
    case claudeNotFound

    var errorDescription: String? {
        switch self {
        case .claudeFailed(let code, let err):
            return "claude -p failed (code \(code)): \(err)"
        case .claudeNotFound:
            return "Claude CLI not found. Install it from https://claude.ai/code"
        }
    }
}
