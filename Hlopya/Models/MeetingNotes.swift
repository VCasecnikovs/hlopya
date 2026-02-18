import Foundation

/// Structured meeting notes - matches existing notes.json schema
struct MeetingNotes: Codable {
    var title: String?
    var date: String?
    var participants: [String]?
    var summary: String?
    var enrichedNotes: String?
    var topics: [Topic]?
    var decisions: [String]?
    var actionItems: [ActionItem]?
    var insights: [String]?
    var followUps: [String]?
    var modelUsed: String?
    var transcriptStats: TranscriptStats?

    // Fallback when JSON parsing fails
    var rawText: String?
    var parseError: Bool?

    enum CodingKeys: String, CodingKey {
        case title, date, participants, summary, decisions, insights, topics
        case enrichedNotes = "enriched_notes"
        case actionItems = "action_items"
        case followUps = "follow_ups"
        case modelUsed = "model_used"
        case transcriptStats = "transcript_stats"
        case rawText = "raw_text"
        case parseError = "parse_error"
    }
}

struct Topic: Codable {
    let topic: String
    let details: String
}

struct ActionItem: Codable, Identifiable {
    var id: String { "\(owner ?? "?")-\(task)" }

    var owner: String?
    let task: String
    var deadline: String?
    var context: String?
}

struct TranscriptStats: Codable {
    var segments: Int?
    var duration: Double?
    var sttModel: String?

    enum CodingKeys: String, CodingKey {
        case segments, duration
        case sttModel = "stt_model"
    }
}
