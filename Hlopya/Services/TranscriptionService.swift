import Foundation
import FluidAudio

/// Transcription service using FluidAudio's Parakeet v3 CoreML model.
/// Replaces the Python transcriber.py pipeline.
@MainActor
@Observable
final class TranscriptionService {
    private(set) var isModelLoaded = false
    private(set) var isDownloading = false
    private(set) var downloadProgress: Double = 0

    private var asrManager: AsrManager?
    private var models: AsrModels?

    /// Download and load the Parakeet v3 model (~400MB)
    func loadModel() async throws {
        guard !isModelLoaded else { return }
        isDownloading = true
        defer { isDownloading = false }

        let loadedModels = try await AsrModels.downloadAndLoad(version: .v3)
        models = loadedModels

        let manager = AsrManager(config: .default)
        try await manager.initialize(models: loadedModels)
        asrManager = manager

        isModelLoaded = true
        print("[TranscriptionService] Parakeet v3 model loaded")
    }

    /// Transcribe a complete meeting from mic.wav and system.wav
    func transcribeMeeting(sessionDir: URL) async throws -> TranscriptResult {
        guard let asr = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        let startTime = Date()
        let micPath = sessionDir.appendingPathComponent("mic.wav").path
        let sysPath = sessionDir.appendingPathComponent("system.wav").path

        // Load audio samples
        let converter = AudioConverter()
        let micSamples = try converter.resampleAudioFile(path: micPath)
        let sysSamples = try converter.resampleAudioFile(path: sysPath)

        // Echo cancellation
        print("[Transcription] Removing echo from mic channel...")
        let cleanedMic = EchoCancellation.removeEcho(
            micSamples: micSamples,
            systemSamples: sysSamples
        )

        // Transcribe both channels
        print("[Transcription] Transcribing mic (Me)...")
        let micResult = try await asr.transcribe(cleanedMic, source: .microphone)

        print("[Transcription] Transcribing system (Them)...")
        let sysResult = try await asr.transcribe(sysSamples, source: .system)

        // Build segments from results
        let micSegments = buildSegments(from: micResult, speaker: "Me")
        let sysSegments = buildSegments(from: sysResult, speaker: "Them")

        // Merge and sort by timestamp
        var allSegments = micSegments + sysSegments
        allSegments.sort { $0.start < $1.start }
        allSegments = allSegments.filter { !$0.text.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty }

        // Build formatted transcript
        let lines = allSegments.map { seg -> String in
            let ts = seg.start > 0 ? "[\(String(format: "%.1f", seg.start))s]" : ""
            return "**\(seg.speaker)** \(ts): \(seg.text)"
        }
        let fullText = lines.joined(separator: "\n")
        let elapsed = Date().timeIntervalSince(startTime)

        let result = TranscriptResult(
            segments: allSegments,
            fullText: fullText,
            plainText: allSegments.map { $0.text }.joined(separator: " "),
            meText: allSegments.filter { $0.speaker == "Me" }.map { $0.text }.joined(separator: " "),
            themText: allSegments.filter { $0.speaker == "Them" }.map { $0.text }.joined(separator: " "),
            numSegments: allSegments.count,
            durationSeconds: allSegments.last?.end ?? 0,
            processingTime: elapsed,
            modelUsed: "parakeet-v3-coreml"
        )

        print("[Transcription] Done: \(result.numSegments) segments in \(String(format: "%.1f", elapsed))s")
        return result
    }

    private func buildSegments(from result: ASRResult, speaker: String) -> [TranscriptSegment] {
        // ASRResult contains text and timing info
        // We treat the whole result as one segment if no word timings available
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        // Try to split into sentences for better segmentation
        let sentences = splitIntoSentences(text)
        if sentences.count <= 1 {
            return [TranscriptSegment(speaker: speaker, start: 0, end: 0, text: text)]
        }

        // Distribute timestamps evenly across sentences (rough approximation)
        return sentences.enumerated().map { idx, sentence in
            TranscriptSegment(
                speaker: speaker,
                start: 0,
                end: 0,
                text: sentence
            )
        }
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case noAudioFiles
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "STT model not loaded. Download it first."
        case .noAudioFiles: return "No audio files found in session directory"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        }
    }
}
