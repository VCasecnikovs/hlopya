// audiocap - Capture system audio using ScreenCaptureKit (macOS 13+)
// Outputs WAV files for system audio and optionally microphone
// No BlackHole needed - uses Apple's ScreenCaptureKit audio stream
//
// Usage: audiocap <output.wav> [--sample-rate 16000] [--mic]
// Stop: Ctrl+C or SIGTERM - files are finalized cleanly

import Foundation
import AVFoundation
import ScreenCaptureKit

// MARK: - WAV Writer

class WAVWriter {
    private let fileHandle: FileHandle
    let sampleRate: Int
    let channels: Int
    private var dataSize: UInt32 = 0
    let filePath: String

    init(path: String, sampleRate: Int, channels: Int = 1) throws {
        self.filePath = path
        self.sampleRate = sampleRate
        self.channels = channels
        FileManager.default.createFile(atPath: path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        writeHeader()
    }

    private func writeHeader() {
        fileHandle.seek(toFileOffset: 0)
        var h = Data()
        let bps: UInt16 = 2 // 16-bit PCM
        let ba = UInt16(channels) * bps
        let br = UInt32(sampleRate) * UInt32(ba)
        h.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        withUnsafeBytes(of: (dataSize + 36).littleEndian) { h.append(contentsOf: $0) }
        h.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        h.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        withUnsafeBytes(of: UInt32(16).littleEndian) { h.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { h.append(contentsOf: $0) } // PCM int16
        withUnsafeBytes(of: UInt16(channels).littleEndian) { h.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { h.append(contentsOf: $0) }
        withUnsafeBytes(of: br.littleEndian) { h.append(contentsOf: $0) }
        withUnsafeBytes(of: ba.littleEndian) { h.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(bps * 8).littleEndian) { h.append(contentsOf: $0) }
        h.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        withUnsafeBytes(of: dataSize.littleEndian) { h.append(contentsOf: $0) }
        fileHandle.write(h)
    }

    func write(samples: Data) {
        fileHandle.seekToEndOfFile()
        fileHandle.write(samples)
        dataSize += UInt32(samples.count)
    }

    func close() {
        writeHeader() // rewrite with final size
        fileHandle.closeFile()
        let dur = Double(dataSize) / Double(UInt32(sampleRate) * UInt32(channels) * 2) // 2 bytes per sample (int16)
        log("Audio saved: \(filePath) (\(String(format: "%.1f", dur))s)")
    }
}

// MARK: - System Audio Capture via ScreenCaptureKit

class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let writer: WAVWriter
    let targetRate: Int
    private var stream: SCStream?
    private var converter: AVAudioConverter?
    var sampleCount = 0

    init(writer: WAVWriter, targetRate: Int) {
        self.writer = writer
        self.targetRate = targetRate
    }

    func start() async throws {
        // Get shareable content (triggers permission dialog if needed)
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw "No displays found"
        }

        // Configure for audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.sampleRate = targetRate
        config.channelCount = 1

        // Minimal video (required but we won't use it)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

        // Create a content filter for the display (captures all audio)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream!.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio-queue"))

        try await stream!.startCapture()
        log("System audio capture started via ScreenCaptureKit")
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // Get the audio buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return }

        // Get format description
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return }

        var rawData = Data(count: length)
        rawData.withUnsafeMutableBytes { ptr in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
        }

        // Convert float32 to int16 and write
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if isFloat {
            // Float32 -> Int16
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
            // Already int16
            writer.write(samples: rawData)
            sampleCount += length / 2
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        log("Stream stopped with error: \(error.localizedDescription)")
    }

    func stop() async {
        if let stream = stream {
            try? await stream.stopCapture()
        }
    }
}

// MARK: - Mic Recorder

class MicRecorder {
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
            guard outFrames > 0 else { return }
            guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outFrames) else { return }
            var done = false
            converter.convert(to: out, error: nil) { _, s in
                if done { s.pointee = .noDataNow; return nil }
                done = true; s.pointee = .haveData; return buf
            }
            if let ch = out.int16ChannelData, out.frameLength > 0 {
                self.writer.write(samples: Data(bytes: ch[0], count: Int(out.frameLength) * 2))
            }
        }
        try engine.start()
        log("Mic recording started")
    }

    func stop() { engine.stop(); writer.close() }
}

// MARK: - Main

func log(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

extension String: @retroactive Error {}

// Parse args
var outputPath = "system.wav"
var sampleRate = 16000
var captureMic = false

let args = CommandLine.arguments
var i = 1
while i < args.count {
    switch args[i] {
    case "--sample-rate": i += 1; sampleRate = Int(args[i]) ?? 16000
    case "--mic": captureMic = true
    case "--help", "-h":
        FileHandle.standardOutput.write("audiocap - System audio capture via ScreenCaptureKit\nUsage: audiocap [output.wav] [--sample-rate 16000] [--mic]\nStop with Ctrl+C.\nRequires macOS 13+ and Screen Recording permission.\n".data(using: .utf8)!)
        _Exit(0)
    default:
        if !args[i].hasPrefix("-") { outputPath = args[i] }
    }
    i += 1
}

var sysCapture: SystemAudioCapture?
var micRec: MicRecorder?

// Async startup
Task {
    do {
        let sysWriter = try WAVWriter(path: outputPath, sampleRate: sampleRate)
        sysCapture = SystemAudioCapture(writer: sysWriter, targetRate: sampleRate)
        try await sysCapture!.start()
        log("Recording system audio to: \(outputPath)")

        if captureMic {
            let micPath = URL(fileURLWithPath: outputPath).deletingLastPathComponent().appendingPathComponent("mic.wav").path
            let micWriter = try WAVWriter(path: micPath, sampleRate: sampleRate)
            micRec = MicRecorder(writer: micWriter, targetRate: sampleRate)
            try micRec?.start()
            log("Mic recording to: \(micPath)")
        }

        log("Press Ctrl+C to stop.")
    } catch {
        log("Error: \(error)")
        exit(1)
    }
}

// Signal handlers
func shutdown() {
    log("\nStopping...")
    Task {
        await sysCapture?.stop()
        sysCapture?.writer.close()
        micRec?.stop()
        log("Done. System samples: \(sysCapture?.sampleCount ?? 0)")
        exit(0)
    }
}

signal(SIGINT) { _ in shutdown() }
signal(SIGTERM) { _ in shutdown() }

// Run forever
dispatchMain()
