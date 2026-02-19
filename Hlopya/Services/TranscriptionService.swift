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

    /// Download and load the Parakeet v3 model (~400MB).
    /// Model files are cached on disk after first download, so subsequent loads
    /// only need CoreML compilation (~2-3s).
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

    /// Release model from memory. Model files remain cached on disk
    /// for fast reload. Frees ~400MB RAM.
    func unloadModel() {
        asrManager = nil
        models = nil
        isModelLoaded = false
        print("[TranscriptionService] Model unloaded from memory")
    }

    /// Configure vocabulary boosting with CTC rescoring
    func configureVocabulary(context: CustomVocabularyContext) async throws {
        guard let asr = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        print("[TranscriptionService] Loading CTC model for vocabulary boosting...")
        let ctcModels = try await CtcModels.downloadAndLoad()
        try await asr.configureVocabularyBoosting(vocabulary: context, ctcModels: ctcModels)
        print("[TranscriptionService] Vocabulary boosting configured with \(context.terms.count) terms")
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

        // Duration from ASR results (not segment timestamps which can be 0)
        let audioDuration = max(micResult.duration, sysResult.duration)

        // Overall confidence: weighted average from segments that have confidence
        let segmentsWithConf = allSegments.compactMap(\.confidence)
        let overallConfidence: Float? = segmentsWithConf.isEmpty ? nil :
            segmentsWithConf.reduce(0, +) / Float(segmentsWithConf.count)

        // RTFX: how many times faster than realtime
        let rtfx: Float? = elapsed > 0 && audioDuration > 0 ? Float(audioDuration / elapsed) : nil

        let result = TranscriptResult(
            segments: allSegments,
            fullText: fullText,
            plainText: allSegments.map { $0.text }.joined(separator: " "),
            meText: allSegments.filter { $0.speaker == "Me" }.map { $0.text }.joined(separator: " "),
            themText: allSegments.filter { $0.speaker == "Them" }.map { $0.text }.joined(separator: " "),
            numSegments: allSegments.count,
            durationSeconds: audioDuration,
            processingTime: elapsed,
            modelUsed: "parakeet-v3-coreml",
            confidence: overallConfidence,
            rtfx: rtfx
        )

        print("[Transcription] Done: \(result.numSegments) segments in \(String(format: "%.1f", elapsed))s, confidence: \(overallConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "N/A"), rtfx: \(rtfx.map { String(format: "%.1fx", $0) } ?? "N/A")")
        return result
    }

    private func buildSegments(from result: ASRResult, speaker: String) -> [TranscriptSegment] {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        // Use token timings if available (Parakeet v3 provides these)
        if let timings = result.tokenTimings, !timings.isEmpty {
            return buildSegmentsFromTimings(timings, speaker: speaker, audioDuration: result.duration)
        }

        // Fallback: distribute evenly across audio duration
        let sentences = splitIntoSentences(text)
        let duration = result.duration > 0 ? result.duration : 1.0
        let perSentence = duration / Double(sentences.count)

        return sentences.enumerated().map { idx, sentence in
            TranscriptSegment(
                speaker: speaker,
                start: Double(idx) * perSentence,
                end: Double(idx + 1) * perSentence,
                text: sentence
            )
        }
    }

    /// Group token timings into sentence-level segments with real timestamps
    private func buildSegmentsFromTimings(_ timings: [TokenTiming], speaker: String, audioDuration: TimeInterval) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var currentTokens: [TokenTiming] = []

        // Sentence-ending punctuation
        let sentenceEnders: Set<Character> = [".", "!", "?"]
        // Minimum segment duration (seconds) to avoid micro-segments
        let minSegmentDuration: Double = 2.0
        // Maximum segment duration before forcing a split
        let maxSegmentDuration: Double = 30.0

        for timing in timings {
            currentTokens.append(timing)

            let tokenText = timing.token.trimmingCharacters(in: .whitespaces)
            let endsWithPunctuation = tokenText.last.map { sentenceEnders.contains($0) } ?? false
            let segmentDuration = (currentTokens.last?.endTime ?? 0) - (currentTokens.first?.startTime ?? 0)

            // Split on sentence boundary (if long enough) or when segment is too long
            let shouldSplit = (endsWithPunctuation && segmentDuration >= minSegmentDuration)
                || segmentDuration >= maxSegmentDuration

            if shouldSplit {
                if let seg = makeSegment(from: currentTokens, speaker: speaker) {
                    segments.append(seg)
                }
                currentTokens = []
            }
        }

        // Flush remaining tokens
        if !currentTokens.isEmpty {
            if let seg = makeSegment(from: currentTokens, speaker: speaker) {
                segments.append(seg)
            }
        }

        return segments
    }

    /// Create a TranscriptSegment from a group of tokens
    private func makeSegment(from tokens: [TokenTiming], speaker: String) -> TranscriptSegment? {
        let text = tokens.map { $0.token }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let start = tokens.first?.startTime ?? 0
        let end = tokens.last?.endTime ?? start
        let avgConfidence = tokens.isEmpty ? nil : tokens.map(\.confidence).reduce(0, +) / Float(tokens.count)
        return TranscriptSegment(speaker: speaker, start: start, end: end, text: text, confidence: avgConfidence)
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
