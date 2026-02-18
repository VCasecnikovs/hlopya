import Foundation
import AudioToolbox
import AVFoundation
import CoreAudio

/// Captures system audio via Core Audio Taps and microphone via AVAudioEngine.
/// Uses "System Audio Recording Only" permission (not Screen Recording).
@MainActor
@Observable
final class AudioCaptureService {
    private(set) var isRecording = false
    private(set) var elapsedTime: TimeInterval = 0
    var lastError: String?

    private var systemTap: SystemAudioTap?
    private var micRecorder: MicRecorder?
    private var timer: Timer?
    private(set) var startTime: Date?

    let sampleRate = 16000

    func startRecording(sessionDir: URL) async throws {
        lastError = nil

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

        // System audio via Core Audio Taps (triggers "System Audio Recording Only" permission)
        NSLog("[Hlopya] Starting system audio capture via Core Audio Taps...")
        let sysWriter = try WAVWriter(path: sysPath, sampleRate: sampleRate)
        systemTap = SystemAudioTap(writer: sysWriter, targetRate: sampleRate)
        try systemTap!.start()

        // Microphone via AVAudioEngine
        NSLog("[Hlopya] Starting microphone capture...")
        let micWriter = try WAVWriter(path: micPath, sampleRate: sampleRate)
        micRecorder = MicRecorder(writer: micWriter, targetRate: sampleRate)
        try micRecorder!.start()

        startTime = Date()
        isRecording = true
        elapsedTime = 0

        // Update elapsed time every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }

        NSLog("[Hlopya] Recording started")
    }

    func stopRecording() async {
        timer?.invalidate()
        timer = nil

        systemTap?.stop()
        systemTap?.writer.close()
        systemTap = nil

        micRecorder?.stop()
        micRecorder = nil

        isRecording = false
        startTime = nil
        NSLog("[Hlopya] Recording stopped")
    }

    var formattedTime: String {
        let total = Int(elapsedTime)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - System Audio Capture via Core Audio Taps (macOS 14.2+)

/// Captures all system audio output using CATapDescription + AudioHardwareCreateProcessTap.
/// This triggers the "System Audio Recording Only" permission (not "Screen Recording").
final class SystemAudioTap {
    let writer: WAVWriter
    let targetRate: Int

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var deviceProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "hlopya.system-audio", qos: .userInteractive)

    init(writer: WAVWriter, targetRate: Int) {
        self.writer = writer
        self.targetRate = targetRate
    }

    func start() throws {
        // 1. Create global audio tap (captures all system audio)
        let tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDesc.uuid = UUID()
        tapDesc.muteBehavior = .unmuted

        var outTapID: AudioObjectID = kAudioObjectUnknown
        var err = AudioHardwareCreateProcessTap(tapDesc, &outTapID)
        guard err == noErr else {
            throw AudioCaptureError.systemAudioFailed("Process tap creation failed (error \(err)). Grant 'System Audio Recording Only' in System Settings > Privacy & Security.")
        }
        tapID = outTapID
        NSLog("[SystemAudioTap] Created process tap #%d", tapID)

        // 2. Read tap's audio format
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        err = AudioObjectGetPropertyData(tapID, &formatAddr, 0, nil, &formatSize, &format)
        guard err == noErr else {
            throw AudioCaptureError.systemAudioFailed("Failed to read tap format (error \(err))")
        }
        NSLog("[SystemAudioTap] Format: %.0f Hz, %d ch, %d bits, flags=0x%X",
              format.mSampleRate, format.mChannelsPerFrame, format.mBitsPerChannel, format.mFormatFlags)

        // 3. Get system output device UID
        var outputDeviceID: AudioDeviceID = kAudioObjectUnknown
        var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddr, 0, nil, &propSize, &outputDeviceID)
        guard err == noErr else {
            throw AudioCaptureError.systemAudioFailed("Failed to get system output device (error \(err))")
        }

        var uidCFStr: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        err = AudioObjectGetPropertyData(outputDeviceID, &uidAddr, 0, nil, &uidSize, &uidCFStr)
        guard err == noErr else {
            throw AudioCaptureError.systemAudioFailed("Failed to read device UID (error \(err))")
        }
        let outputUID = uidCFStr as String
        NSLog("[SystemAudioTap] System output device: %@", outputUID)

        // 4. Create aggregate device with the tap attached
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hlopya-Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDesc.uuid.uuidString
                ]
            ]
        ]

        aggregateDeviceID = kAudioObjectUnknown
        err = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            throw AudioCaptureError.systemAudioFailed("Aggregate device creation failed (error \(err))")
        }
        NSLog("[SystemAudioTap] Created aggregate device #%d", aggregateDeviceID)

        // 5. Start audio I/O
        let channels = max(Int(format.mChannelsPerFrame), 1)
        let srcRate = format.mSampleRate
        let dstRate = Double(targetRate)
        let ratio = srcRate / dstRate
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0

        NSLog("[SystemAudioTap] Float=%d, NonInterleaved=%d, channels=%d, ratio=%.2f",
              isFloat ? 1 : 0, isNonInterleaved ? 1 : 0, channels, ratio)

        err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) {
            [weak self] _, inInputData, _, _, _ in
            guard let self else { return }

            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            guard !abl.isEmpty else { return }

            if isFloat {
                self.processFloatAudio(abl: abl, channels: channels,
                                       isNonInterleaved: isNonInterleaved,
                                       ratio: ratio)
            } else {
                // int16 format - just resample
                self.processInt16Audio(abl: abl, channels: channels,
                                       isNonInterleaved: isNonInterleaved,
                                       ratio: ratio)
            }
        }
        guard err == noErr else {
            throw AudioCaptureError.systemAudioFailed("IO proc creation failed (error \(err))")
        }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            throw AudioCaptureError.systemAudioFailed("Device start failed (error \(err))")
        }
        NSLog("[SystemAudioTap] Capturing system audio")
    }

    // MARK: - Audio Processing

    private func processFloatAudio(abl: UnsafeMutableAudioBufferListPointer,
                                    channels: Int,
                                    isNonInterleaved: Bool,
                                    ratio: Double) {
        let frameCount: Int
        let monoSamples: UnsafeMutableBufferPointer<Float>

        if isNonInterleaved {
            // Each buffer = one channel
            guard let ch0Data = abl[0].mData else { return }
            let ch0 = ch0Data.assumingMemoryBound(to: Float.self)
            frameCount = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
            guard frameCount > 0 else { return }

            let mono = UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
            defer { mono.deallocate() }

            if channels >= 2 && abl.count > 1, let ch1Data = abl[1].mData {
                let ch1 = ch1Data.assumingMemoryBound(to: Float.self)
                for i in 0..<frameCount {
                    mono[i] = (ch0[i] + ch1[i]) * 0.5
                }
            } else {
                for i in 0..<frameCount {
                    mono[i] = ch0[i]
                }
            }
            monoSamples = mono
        } else {
            // Interleaved: L R L R ...
            guard let data = abl[0].mData else { return }
            let floats = data.assumingMemoryBound(to: Float.self)
            frameCount = Int(abl[0].mDataByteSize) / (MemoryLayout<Float>.size * channels)
            guard frameCount > 0 else { return }

            let mono = UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
            defer { mono.deallocate() }

            if channels >= 2 {
                for i in 0..<frameCount {
                    mono[i] = (floats[i * channels] + floats[i * channels + 1]) * 0.5
                }
            } else {
                for i in 0..<frameCount {
                    mono[i] = floats[i]
                }
            }
            monoSamples = mono
        }

        // Resample and convert to int16
        let outCount = Int(Double(frameCount) / ratio)
        guard outCount > 0 else { return }

        var int16Data = Data(count: outCount * 2)
        int16Data.withUnsafeMutableBytes { ptr in
            let shorts = ptr.bindMemory(to: Int16.self)
            for i in 0..<outCount {
                let srcIdx = min(Int(Double(i) * ratio), frameCount - 1)
                let clamped = max(Float(-1.0), min(Float(1.0), monoSamples[srcIdx]))
                shorts[i] = Int16(clamped * 32767.0)
            }
        }

        writer.write(samples: int16Data)
    }

    private func processInt16Audio(abl: UnsafeMutableAudioBufferListPointer,
                                    channels: Int,
                                    isNonInterleaved: Bool,
                                    ratio: Double) {
        guard let data = abl[0].mData else { return }
        let samples = data.assumingMemoryBound(to: Int16.self)
        let sampleCount = Int(abl[0].mDataByteSize) / MemoryLayout<Int16>.size
        let frameCount = isNonInterleaved ? sampleCount : sampleCount / channels
        guard frameCount > 0 else { return }

        let outCount = Int(Double(frameCount) / ratio)
        guard outCount > 0 else { return }

        var int16Data = Data(count: outCount * 2)
        int16Data.withUnsafeMutableBytes { ptr in
            let shorts = ptr.bindMemory(to: Int16.self)
            if isNonInterleaved || channels == 1 {
                for i in 0..<outCount {
                    let srcIdx = min(Int(Double(i) * ratio), frameCount - 1)
                    shorts[i] = samples[srcIdx]
                }
            } else {
                // Interleaved stereo - mix to mono
                for i in 0..<outCount {
                    let srcIdx = min(Int(Double(i) * ratio), frameCount - 1)
                    let l = Int32(samples[srcIdx * channels])
                    let r = Int32(samples[srcIdx * channels + 1])
                    shorts[i] = Int16((l + r) / 2)
                }
            }
        }

        writer.write(samples: int16Data)
    }

    func stop() {
        if aggregateDeviceID != kAudioObjectUnknown {
            if let procID = deviceProcID {
                AudioDeviceStop(aggregateDeviceID, procID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
                deviceProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        NSLog("[SystemAudioTap] Stopped and cleaned up")
    }

    deinit { stop() }
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
    case micPermissionDenied
    case systemAudioFailed(String)

    var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            return "Microphone permission required. Go to System Settings > Privacy & Security > Microphone and enable Hlopya."
        case .systemAudioFailed(let msg):
            return msg
        }
    }
}
