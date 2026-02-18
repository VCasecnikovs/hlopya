import Foundation

/// Exports meeting notes to Obsidian vault at ~/Documents/MyBrain/Meetings/
final class ObsidianExporter {

    let meetingsDir: URL

    init(vaultPath: String = "~/Documents/MyBrain") {
        let expanded = NSString(string: vaultPath).expandingTildeInPath
        self.meetingsDir = URL(fileURLWithPath: expanded).appendingPathComponent("Meetings")
        try? FileManager.default.createDirectory(at: meetingsDir, withIntermediateDirectories: true)
    }

    /// Export notes to Obsidian markdown format
    func export(notes: MeetingNotes, sessionId: String) throws -> URL {
        let title = notes.title ?? sessionId
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileName = "\(sessionId.prefix(10)) \(safeTitle).md"
        let filePath = meetingsDir.appendingPathComponent(fileName)

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
