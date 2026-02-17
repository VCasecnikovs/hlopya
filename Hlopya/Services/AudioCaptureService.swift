import Foundation
import AVFoundation
import ScreenCaptureKit

/// Captures system audio via ScreenCaptureKit and microphone via AVAudioEngine.
/// Replaces the external audiocap subprocess - everything runs in-process.
@MainActor
final class AudioCaptureService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published var lastError: String?

    private var systemCapture: SystemAudioCapture?
    private var micRecorder: MicRecorder?
    private var timer: Timer?
    private var startTime: Date?

    let sampleRate = 16000

    /// Check if screen recording permission is granted
    var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request screen recording permission (opens System Settings)
    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    func startRecording(sessionDir: URL) async throws {
        lastError = nil

        // Check screen recording permission
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            throw AudioCaptureError.permissionDenied
        }

        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw AudioCaptureError.micPermissionDenied }
        default:
            throw AudioCaptureError.micPermissionDenied
        }

        let sysPath = sessionDir.appendingPathComponent("system.wav").path
        let micPath = sessionDir.appendingPathComponent("mic.wav").path

        // System audio via ScreenCaptureKit (audio-only, no screen content)
        let sysWriter = try WAVWriter(path: sysPath, sampleRate: sampleRate)
        systemCapture = SystemAudioCapture(writer: sysWriter, targetRate: sampleRate)
        try await systemCapture!.start()

        // Microphone via AVAudioEngine
        let micWriter = try WAVWriter(path: micPath, sampleRate: sampleRate)
        micRecorder = MicRecorder(writer: micWriter, targetRate: sampleRate)
        try micRecorder!.start()

        startTime = Date()
        isRecording = true

        // Update elapsed time every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    func stopRecording() async {
        timer?.invalidate()
        timer = nil

        await systemCapture?.stop()
        systemCapture?.writer.close()
        systemCapture = nil

        micRecorder?.stop()
        micRecorder = nil

        isRecording = false
        startTime = nil
    }

    var formattedTime: String {
        let total = Int(elapsedTime)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - System Audio Capture via ScreenCaptureKit

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let writer: WAVWriter
    let targetRate: Int
    private var stream: SCStream?
    var sampleCount = 0

    init(writer: WAVWriter, targetRate: Int) {
        self.writer = writer
        self.targetRate = targetRate
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplays
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = targetRate
        config.channelCount = 1

        // Audio-only: no video capture. On macOS 15+ this makes the app
        // appear under "System Audio Recording Only" instead of "Screen Recording"
        config.width = 1
        config.height = 1
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale.max)
        config.showsCursor = false

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        // Only audio output - no video output added
        try stream!.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "hlopya.audio-queue"))
        try await stream!.startCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return }

        var rawData = Data(count: length)
        _ = rawData.withUnsafeMutableBytes { ptr in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
        }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if isFloat {
            let floatCount = length / 4
            var int16Data = Data(count: floatCount * 2)
            rawData.withUnsafeBytes { srcPtr in
                int16Data.withUnsafeMutableBytes { dstPtr in
                    let floats = srcPtr.bindMemory(to: Float.self)
                    let shorts = dstPtr.bindMemory(to: Int16.self)
                    for i in 0..<floatCount {
                        let clamped = max(-1.0, min(1.0, floats[i]))
                        shorts[i] = Int16(clamped * 32767.0)
                    }
                }
            }
            writer.write(samples: int16Data)
            sampleCount += floatCount
        } else {
            writer.write(samples: rawData)
            sampleCount += length / 2
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        print("[SystemAudio] Stream stopped: \(error.localizedDescription)")
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
    }
}

// MARK: - Microphone Recorder via AVAudioEngine

final class MicRecorder {
    let writer: WAVWriter
    let engine = AVAudioEngine()
    let targetRate: Int

    init(writer: WAVWriter, targetRate: Int) {
        self.writer = writer
        self.targetRate = targetRate
    }

    func start() throws {
        let node = engine.inputNode
        let fmt = node.outputFormat(forBus: 0)
        let outFmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(targetRate), channels: 1, interleaved: true)!
        let converter = AVAudioConverter(from: fmt, to: outFmt)!

        node.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, _ in
            guard let self else { return }
            let outFrames = AVAudioFrameCount(Double(buf.frameLength) * Double(self.targetRate) / fmt.sampleRate)
            guard outFrames > 0,
                  let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outFrames) else { return }

            var done = false
            converter.convert(to: out, error: nil) { _, status in
                if done { status.pointee = .noDataNow; return nil }
                done = true; status.pointee = .haveData; return buf
            }

            if let ch = out.int16ChannelData, out.frameLength > 0 {
                self.writer.write(samples: Data(bytes: ch[0], count: Int(out.frameLength) * 2))
            }
        }

        try engine.start()
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        writer.close()
    }
}

// MARK: - Errors

enum AudioCaptureError: LocalizedError {
    case noDisplays
    case permissionDenied
    case micPermissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplays: return "No displays found for audio capture"
        case .permissionDenied: return "Screen Recording permission required. Go to System Settings > Privacy & Security > Screen Recording and enable Hlopya."
        case .micPermissionDenied: return "Microphone permission required. Go to System Settings > Privacy & Security > Microphone and enable Hlopya."
        }
    }
}
