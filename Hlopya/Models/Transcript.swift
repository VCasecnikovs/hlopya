import Foundation

/// A single segment of transcribed speech
struct TranscriptSegment: Codable, Identifiable {
    var id: String { "\(speaker)-\(start)-\(end)" }

    let speaker: String   // "Me" or "Them"
    let start: Double     // seconds
    let end: Double       // seconds
    let text: String
    var language: String?
    var confidence: Float?
}

/// Complete transcript result - matches existing transcript.json schema
struct TranscriptResult: Codable {
    let segments: [TranscriptSegment]
    let fullText: String
    let plainText: String
    let meText: String
    let themText: String
    let numSegments: Int
    let durationSeconds: Double
    let processingTime: Double
    let modelUsed: String
    var confidence: Float?
    var rtfx: Float?

    enum CodingKeys: String, CodingKey {
        case segments
        case fullText = "full_text"
        case plainText = "plain_text"
        case meText = "me_text"
        case themText = "them_text"
        case numSegments = "num_segments"
        case durationSeconds = "duration_seconds"
        case processingTime = "processing_time"
        case modelUsed = "model_used"
        case confidence
        case rtfx
    }
}
