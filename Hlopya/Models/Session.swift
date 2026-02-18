import Foundation

/// Represents a recording session stored in ~/recordings/{YYYY-MM-DD_HH-MM-SS}/
struct Session: Identifiable, Codable, Hashable {
    let id: String  // Directory name: YYYY-MM-DD_HH-MM-SS

    var title: String?
    var participants: [String]
    var participantNames: [String: String]  // "Me" -> "Vadim", "Them" -> "Alex"
    var duration: TimeInterval
    var status: SessionStatus

    var hasMic: Bool
    var hasSystem: Bool
    var hasTranscript: Bool
    var hasNotes: Bool
    var hasPersonalNotes: Bool

    var date: Date {
        Session.dateFormatter.date(from: id) ?? Date()
    }

    var displayTitle: String {
        title ?? id.replacingOccurrences(of: "_", with: " ")
    }

    var directoryURL: URL {
        Session.recordingsDirectory.appendingPathComponent(id)
    }

    // MARK: - Static

    static let recordingsDirectory: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("recordings")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM HH:mm"
        return f
    }()

    static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' HH:mm"
        return f
    }()

    static func newSessionId() -> String {
        dateFormatter.string(from: Date())
    }
}

enum SessionStatus: String, Codable {
    case recording
    case recorded
    case transcribed
    case done
}

/// Metadata stored in meta.json
struct SessionMeta: Codable {
    var title: String?
    var participantNames: [String: String]?

    enum CodingKeys: String, CodingKey {
        case title
        case participantNames = "participant_names"
    }
}
