import Foundation

/// Exports meeting notes as Markdown into the configured notes folder
/// (the `obsidianVault` setting). One `.md` per session, written directly
/// into that folder (no implicit subfolder).
final class ObsidianExporter {

    let notesDir: URL

    init(vaultPath: String? = nil) {
        let raw = vaultPath ?? UserDefaults.standard.string(forKey: "obsidianVault") ?? "~/Documents/MyBrain"
        let expanded = NSString(string: raw).expandingTildeInPath
        self.notesDir = URL(fileURLWithPath: expanded, isDirectory: true)
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
    }

    /// Export notes to Obsidian markdown format
    func export(notes: MeetingNotes, sessionId: String) throws -> URL {
        let title = notes.title ?? sessionId
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(sessionId.prefix(10)) \(safeTitle).md"
        let filePath = notesDir.appendingPathComponent(fileName)

        var md = "---\n"
        md += "date: \(notes.date ?? String(sessionId.prefix(10)))\n"
        if let participants = notes.participants, !participants.isEmpty {
            md += "participants:\n"
            for p in participants {
                md += "  - \"[[People/\(p)]]\"\n"
            }
        }
        md += "tags:\n  - meeting\n"
        md += "recorder: hlopya\n"
        md += "session_id: \(sessionId)\n"
        if let model = notes.modelUsed {
            md += "model: \(model)\n"
        }
        md += "---\n\n"

        // Summary
        if let summary = notes.summary {
            md += "## Summary\n\n\(summary)\n\n"
        }

        // Enriched Notes
        if let enriched = notes.enrichedNotes {
            md += "## Notes\n\n\(enriched)\n\n"
        }

        // Decisions
        if let decisions = notes.decisions, !decisions.isEmpty {
            md += "## Decisions\n\n"
            for d in decisions {
                md += "- \(d)\n"
            }
            md += "\n"
        }

        // Action Items
        if let items = notes.actionItems, !items.isEmpty {
            md += "## Action Items\n\n"
            for item in items {
                let owner = item.owner ?? "?"
                let deadline = item.deadline.map { " (due: \($0))" } ?? ""
                md += "- [ ] **\(owner)**: \(item.task)\(deadline)\n"
                if let context = item.context, !context.isEmpty {
                    md += "  - \(context)\n"
                }
            }
            md += "\n"
        }

        // Topics
        if let topics = notes.topics, !topics.isEmpty {
            md += "## Topics\n\n"
            for topic in topics {
                md += "### \(topic.topic)\n\n\(topic.details)\n\n"
            }
        }

        // Insights
        if let insights = notes.insights, !insights.isEmpty {
            md += "## Insights\n\n"
            for i in insights {
                md += "- \(i)\n"
            }
            md += "\n"
        }

        // Follow-ups
        if let followUps = notes.followUps, !followUps.isEmpty {
            md += "## Follow-ups\n\n"
            for f in followUps {
                md += "- \(f)\n"
            }
            md += "\n"
        }

        try md.write(to: filePath, atomically: true, encoding: .utf8)
        print("[ObsidianExporter] Saved: \(filePath.path)")
        return filePath
    }
}
