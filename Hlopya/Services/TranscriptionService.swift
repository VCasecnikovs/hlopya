import Foundation
import FluidAudio

/// Transcription service using FluidAudio's Parakeet v3 CoreML model,
/// with Nemotron 3 Diarization splitting each track into speakers.
/// Replaces the Python transcriber.py pipeline.
@MainActor
@Observable
final class TranscriptionService {
    private(set) var isModelLoaded = false
    private(set) var isDownloading = false
    private(set) var downloadProgress: Double = 0

    var isModelCached: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3))
    }

    private var asrManager: AsrManager?
    private var models: AsrModels?
    private var diarizer: Nemotron3Diarizer?

    /// Download and load the Parakeet v3 model (~400MB).
    /// Model files are cached on disk after first download, so subsequent loads
    /// only need CoreML compilation (~2-3s).
    func loadModel() async throws {
        guard !isModelLoaded else { return }
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        let loadedModels = try await AsrModels.downloadAndLoad(version: .v3) { [weak self] progress in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }
        models = loadedModels

        let manager = AsrManager(config: .default)
        try await manager.loadModels(loadedModels)
        asrManager = manager

        downloadProgress = 1.0
        isModelLoaded = true
        print("[TranscriptionService] Parakeet v3 model loaded")
    }

    /// Release model from memory. Model files remain cached on disk
    /// for fast reload. Frees ~400MB RAM.
    func unloadModel() {
        asrManager = nil
        models = nil
        diarizer = nil
        isModelLoaded = false
        print("[TranscriptionService] Model unloaded from memory")
    }

    /// Configure vocabulary boosting with CTC rescoring
    /// Note: vocabulary boosting requires SlidingWindowAsrManager (streaming mode).
    /// Currently a no-op for offline transcription via AsrManager.
    func configureVocabulary(context: CustomVocabularyContext) async throws {
        guard asrManager != nil else {
            throw TranscriptionError.modelNotLoaded
        }
        print("[TranscriptionService] Vocabulary boosting not available in offline mode (requires SlidingWindowAsrManager)")
    }

    /// Transcribe a complete meeting from mic.wav and system.wav
    func transcribeMeeting(sessionDir: URL) async throws -> TranscriptResult {
        guard let asr = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }

        let startTime = Date()
        guard let micURL = SessionAudio.url(in: sessionDir, track: "mic"),
              let sysURL = SessionAudio.url(in: sessionDir, track: "system") else {
            throw TranscriptionError.noAudioFiles
        }

        // Load audio samples
        let converter = AudioConverter()
        let micSamples = try converter.resampleAudioFile(path: micURL.path)
        let sysSamples = try converter.resampleAudioFile(path: sysURL.path)

        // Echo cancellation
        print("[Transcription] Removing echo from mic channel...")
        // Mic capture runs quiet (peaks around -33 dBFS); boost it so ASR hears distant voices
        let cleanedMic = Self.normalized(EchoCancellation.removeEcho(
            micSamples: micSamples,
            systemSamples: sysSamples
        ))

        // Save cleaned mic waveform for display (200 floats = 800 bytes)
        Self.saveWaveform(cleanedMic, buckets: 200, to: sessionDir.appendingPathComponent("mic_waveform.bin"))

        // Transcribe both channels
        print("[Transcription] Transcribing mic (Me)...")
        let decoderLayers = await asr.decoderLayerCount
        var micState = TdtDecoderState.make(decoderLayers: decoderLayers)
        let micResult = try await asr.transcribe(cleanedMic, decoderState: &micState)

        print("[Transcription] Transcribing system (Them)...")
        var sysState = TdtDecoderState.make(decoderLayers: decoderLayers)
        let sysResult = try await asr.transcribe(sysSamples, decoderState: &sysState)

        // Diarize both channels; failure falls back to plain Me/Them
        let diarizer = await loadDiarizer()
        let micActivity = diarize(cleanedMic, with: diarizer)
        let sysActivity = diarize(sysSamples, with: diarizer)

        // Build segments from results
        let micSegments = buildSegments(from: micResult, activity: micActivity, isMic: true, systemActivity: sysActivity)
        let sysSegments = buildSegments(from: sysResult, activity: sysActivity, isMic: false)

        // Merge, sort, and deduplicate echo segments
        var allSegments = micSegments + sysSegments
        allSegments.sort { $0.start < $1.start }
        allSegments = allSegments.filter { !$0.text.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty }
        let beforeDedup = allSegments.count
        allSegments = Self.deduplicateEchoSegments(allSegments)
        if allSegments.count < beforeDedup {
            print("[Transcription] Removed \(beforeDedup - allSegments.count) echo duplicate(s)")
        }

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
            themText: allSegments.filter { $0.speaker.hasPrefix("Them") }.map { $0.text }.joined(separator: " "),
            numSegments: allSegments.count,
            durationSeconds: audioDuration,
            processingTime: elapsed,
            modelUsed: diarizer != nil ? "parakeet-v3-coreml+nemotron3-diarization" : "parakeet-v3-coreml",
            confidence: overallConfidence,
            rtfx: rtfx
        )

        print("[Transcription] Done: \(result.numSegments) segments in \(String(format: "%.1f", elapsed))s, confidence: \(overallConfidence.map { String(format: "%.0f%%", $0 * 100) } ?? "N/A"), rtfx: \(rtfx.map { String(format: "%.1fx", $0) } ?? "N/A")")
        return result
    }

    /// Load Nemotron 3 Diarization (~190MB, downloaded once). Returns nil if unavailable.
    private func loadDiarizer() async -> Nemotron3Diarizer? {
        if let diarizer { return diarizer }
        do {
            let config = Nemotron3Config.fast128
            let models = try await Nemotron3Models.loadFromHuggingFace(config: config)
            diarizer = Nemotron3Diarizer(config: config, models: models)
            print("[TranscriptionService] Nemotron 3 Diarization loaded")
        } catch {
            print("[TranscriptionService] Diarization unavailable: \(error.localizedDescription)")
        }
        return diarizer
    }

    private func diarize(_ samples: [Float], with diarizer: Nemotron3Diarizer?) -> SpeakerActivity? {
        guard let diarizer, !samples.isEmpty else { return nil }
        do {
            let started = Date()
            let (probs, frames) = try diarizer.processComplete(samples)
            print("[Transcription] Diarized \(samples.count / 16000)s of audio in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            return SpeakerActivity(probabilities: probs, frameCount: frames, numSpeakers: diarizer.config.numSpeakers)
        } catch {
            print("[Transcription] Diarization failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func buildSegments(
        from result: ASRResult, activity: SpeakerActivity?, isMic: Bool, systemActivity: SpeakerActivity? = nil
    ) -> [TranscriptSegment] {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let speaker = isMic ? "Me" : "Them"

        // Use token timings if available (Parakeet v3 provides these)
        if let timings = result.tokenTimings, !timings.isEmpty {
            var words = SpeakerLabeling.words(from: timings, activity: activity)
            if isMic { words = SpeakerLabeling.dropEcho(words, system: systemActivity) }
            words = SpeakerLabeling.mergeMinorSpeakers(
                words,
                // Extra mic voices must be a real participant, not the user split in two
                minShareOfDominant: isMic ? 0.25 : 0.1,
                minWords: isMic ? 150 : 40
            )
            let labels = isMic ? SpeakerLabeling.micLabels(for: words) : SpeakerLabeling.systemLabels(for: words)
            return buildSegmentsFromWords(words) { word in
                word.speaker.flatMap { labels[$0] } ?? speaker
            }
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

    /// Group words into sentence-level segments with real timestamps, splitting on speaker changes
    private func buildSegmentsFromWords(_ words: [SpeakerLabeling.Word], label: (SpeakerLabeling.Word) -> String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var currentTokens: [TokenTiming] = []
        var currentSpeaker = ""

        // Sentence-ending punctuation
        let sentenceEnders: Set<Character> = [".", "!", "?"]
        // Minimum segment duration (seconds) to avoid micro-segments
        let minSegmentDuration: Double = 2.0
        // Maximum segment duration before forcing a split
        let maxSegmentDuration: Double = 30.0

        for word in words {
            let speaker = label(word)
            if speaker != currentSpeaker, !currentTokens.isEmpty {
                if let seg = makeSegment(from: currentTokens, speaker: currentSpeaker) {
                    segments.append(seg)
                }
                currentTokens = []
            }
            currentSpeaker = speaker
            currentTokens.append(contentsOf: word.tokens)

            let tokenText = word.tokens.last?.token.trimmingCharacters(in: .whitespaces) ?? ""
            let endsWithPunctuation = tokenText.last.map { sentenceEnders.contains($0) } ?? false
            let segmentDuration = (currentTokens.last?.endTime ?? 0) - (currentTokens.first?.startTime ?? 0)

            // Split on sentence boundary (if long enough) or when segment is too long
            let shouldSplit = (endsWithPunctuation && segmentDuration >= minSegmentDuration)
                || segmentDuration >= maxSegmentDuration

            if shouldSplit {
                if let seg = makeSegment(from: currentTokens, speaker: currentSpeaker) {
                    segments.append(seg)
                }
                currentTokens = []
            }
        }

        // Flush remaining tokens
        if !currentTokens.isEmpty {
            if let seg = makeSegment(from: currentTokens, speaker: currentSpeaker) {
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

    /// Remove mic segments ("Me" / "Room N") that are echo duplicates of nearby system ("Them...") segments.
    /// The mic picks up speaker output, so the ASR may transcribe the same speech
    /// as both "Me" and "Them". We detect this by comparing word overlap within
    /// a time window and drop the "Me" segment (echo is always in the mic channel).
    private static func deduplicateEchoSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let themSegments = segments.filter { $0.speaker.hasPrefix("Them") }
        guard !themSegments.isEmpty else { return segments }

        let stripPunctuation: (String) -> [String] = { text in
            text.lowercased()
                .unicodeScalars.filter { CharacterSet.letters.contains($0) || $0 == " " }
                .description
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty }
        }

        var echoIndices = Set<Int>()

        for (i, seg) in segments.enumerated() {
            guard !seg.speaker.hasPrefix("Them") else { continue }

            let meWords = stripPunctuation(seg.text)
            guard !meWords.isEmpty else { continue }
            let meJoined = meWords.joined(separator: " ")

            for them in themSegments {
                let timeOverlap = seg.start < them.end + 5 && seg.end > them.start - 5
                guard timeOverlap else { continue }

                let themWords = stripPunctuation(them.text)
                guard !themWords.isEmpty else { continue }
                let themJoined = themWords.joined(separator: " ")

                if meJoined == themJoined || (meWords.count == 1 && themWords.contains(meWords[0])) {
                    echoIndices.insert(i)
                    break
                }

                if meWords.count >= 2 && themJoined.contains(meJoined) {
                    echoIndices.insert(i)
                    break
                }
                if themWords.count >= 2 && meJoined.contains(themJoined) {
                    echoIndices.insert(i)
                    break
                }

                let meSet = Set(meWords)
                let themSet = Set(themWords)
                let common = meSet.intersection(themSet).count

                if common >= 2 {
                    let minSize = min(meSet.count, themSet.count)
                    let overlap = Float(common) / Float(minSize)
                    if overlap > 0.35 {
                        echoIndices.insert(i)
                        break
                    }
                }
            }
        }

        return segments.enumerated().compactMap { i, seg in
            echoIndices.contains(i) ? nil : seg
        }
    }

    /// Scale so the 99.9th-percentile peak sits at 0.9 (ignores clicks), gain capped at 50x.
    static func normalized(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return samples }
        let magnitudes = samples.map(abs).sorted()
        let peak = magnitudes[min(magnitudes.count - 1, Int(Double(magnitudes.count) * 0.999))]
        guard peak > 1e-5 else { return samples }
        let gain = min(0.9 / peak, 50)
        guard gain > 1.05 else { return samples }
        return samples.map { max(-1, min(1, $0 * gain)) }
    }

    private static func saveWaveform(_ samples: [Float], buckets: Int, to url: URL) {
        guard !samples.isEmpty else { return }
        let perBucket = samples.count / buckets
        guard perBucket > 0 else { return }

        var waveform = [Float](repeating: 0, count: buckets)
        for i in 0..<buckets {
            var peak: Float = 0
            let start = i * perBucket
            for j in start..<min(start + perBucket, samples.count) {
                let v = abs(samples[j])
                if v > peak { peak = v }
            }
            waveform[i] = peak
        }
        let maxPeak = waveform.max() ?? 0
        if maxPeak > 0.001 {
            for i in 0..<buckets { waveform[i] /= maxPeak }
        }

        let data = waveform.withUnsafeBufferPointer { Data(buffer: $0) }
        try? data.write(to: url)
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
