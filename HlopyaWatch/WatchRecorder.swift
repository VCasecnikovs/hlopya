import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class WatchRecorder {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var isRecording = false
    private(set) var currentURL: URL?
    private(set) var startedAt: Date?
    private(set) var elapsed: TimeInterval = 0
    var errorMessage: String?

    var formattedElapsed: String {
        let total = Int(elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func toggle() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func start() async {
        errorMessage = nil

        let session = AVAudioSession.sharedInstance()
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else {
            errorMessage = "Microphone permission denied"
            return
        }

        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let url = Self.recordingsDirectory()
                .appendingPathComponent(Self.fileName(for: Date()))

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                AVEncoderBitRateKey: 32_000,
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()

            self.recorder = recorder
            self.currentURL = url
            self.startedAt = Date()
            self.elapsed = 0
            self.isRecording = true
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    static func recordingsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "hlopya-watch-\(formatter.string(from: date)).m4a"
    }
}
