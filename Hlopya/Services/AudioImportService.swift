import AVFoundation
import UniformTypeIdentifiers
import Foundation

/// Converts arbitrary audio files into Hlopya session folders (mic.wav + system.wav + meta.json).
final class AudioImportService {
    var sessionManager: SessionManager?

    static let supportedTypes: [UTType] = [
        .audio, .mpeg4Audio, .mp3, .wav, .aiff,
        UTType("public.flac") ?? .audio,
        UTType("public.aac-audio") ?? .audio,
    ].uniqued()

    struct ImportFailure: Error {
        let filename: String
        let reason: String
    }

    // MARK: - Public

    func importFiles(_ urls: [URL]) async -> (succeeded: Int, failed: [(filename: String, reason: String)]) {
        var succeeded = 0
        var failures: [(String, String)] = []

        for (index, url) in urls.enumerated() {
            do {
                try await importSingle(url, batchIndex: index)
                succeeded += 1
            } catch let e as ImportFailure {
                failures.append((e.filename, e.reason))
            } catch {
                failures.append((url.lastPathComponent, error.localizedDescription))
            }
        }

        await MainActor.run { sessionManager?.loadSessions() }
        return (succeeded, failures)
    }

    // MARK: - Private

    private func importSingle(_ url: URL, batchIndex: Int) async throws {
        let name = url.deletingPathExtension().lastPathComponent
        let base = Session.dateFormatter.string(from: Date())
        let sessionId = batchIndex == 0 ? "\(base)_import" : "\(base)_import-\(batchIndex)"
        let sessionDir = Session.recordingsDirectory.appendingPathComponent(sessionId)

        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        do {
            let micURL = sessionDir.appendingPathComponent("mic.wav")
            let sysURL = sessionDir.appendingPathComponent("system.wav")

            try await convertToWAV(inputURL: url, outputURL: micURL)

            let asset = AVURLAsset(url: micURL)
            let duration = try await asset.load(.duration)
            try writeSilentWAV(at: sysURL, duration: CMTimeGetSeconds(duration))

            let meta: [String: Any] = [
                "title": name,
                "status": SessionStatus.recorded.rawValue,
                "participants": ["Me"],
                "participant_names": [String: String](),
                "meeting_with": "",
                "duration": 0,
            ]
            let data = try JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted)
            try data.write(to: sessionDir.appendingPathComponent("meta.json"))
        } catch {
            try? FileManager.default.removeItem(at: sessionDir)
            throw ImportFailure(filename: url.lastPathComponent, reason: error.localizedDescription)
        }
    }

    private func convertToWAV(inputURL: URL, outputURL: URL) async throws {
        let asset = AVURLAsset(url: inputURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ImportFailure(filename: inputURL.lastPathComponent, reason: "No audio track found")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(readerOutput)

        let writer = try AVAssetWriter(url: outputURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writer.add(writerInput)

        guard reader.startReading() else {
            throw ImportFailure(filename: inputURL.lastPathComponent, reason: reader.error?.localizedDescription ?? "Read failed")
        }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "hlopya.import")) {
                while writerInput.isReadyForMoreMediaData {
                    if let buf = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buf)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }
                }
            }
        }

        if writer.status == .failed {
            throw ImportFailure(filename: inputURL.lastPathComponent, reason: writer.error?.localizedDescription ?? "Write failed")
        }
    }

    private func writeSilentWAV(at url: URL, duration: Double) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!
        let frameCount = AVAudioFrameCount(max(duration * 16_000, 1))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        // Buffer memory is zeroed by default — silence.
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try file.write(from: buffer)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
