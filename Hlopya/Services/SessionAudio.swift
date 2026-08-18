import Foundation

/// Resolves a session's audio tracks, which may be stored compressed (.m4a) or raw (.wav).
///
/// Live capture writes .wav because raw PCM stays recoverable if the app dies mid-meeting.
/// Once a session is transcribed it is transcoded to AAC/.m4a, which AVAudioFile decodes
/// transparently, so playback and transcription work against either form.
enum SessionAudio {
    /// Preferred first: compressed wins when both exist.
    static let supportedExtensions = ["m4a", "wav"]

    static func url(in sessionDir: URL, track: String) -> URL? {
        let fm = FileManager.default
        for ext in supportedExtensions {
            let candidate = sessionDir.appendingPathComponent("\(track).\(ext)")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func exists(in sessionDir: URL, track: String) -> Bool {
        url(in: sessionDir, track: track) != nil
    }
}
