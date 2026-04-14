import AVFoundation
import Combine

@MainActor
@Observable
final class AudioPlayerService {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var micWaveform: [Float] = []
    var systemWaveform: [Float] = []

    private var engine: AVAudioEngine?
    private var micPlayer: AVAudioPlayerNode?
    private var systemPlayer: AVAudioPlayerNode?
    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var displayLink: Timer?
    private var startFrame: AVAudioFramePosition = 0

    func load(micURL: URL, systemURL: URL) {
        stop()

        do {
            let mic = try AVAudioFile(forReading: micURL)
            let sys = try AVAudioFile(forReading: systemURL)
            micFile = mic
            systemFile = sys

            let sampleRate = mic.processingFormat.sampleRate
            duration = Double(max(mic.length, sys.length)) / sampleRate

            micWaveform = Self.extractWaveform(from: mic, buckets: 200)
            systemWaveform = Self.extractWaveform(from: sys, buckets: 200)
        } catch {
            print("[AudioPlayer] Failed to load: \(error)")
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard let micFile, let systemFile else { return }

        if engine == nil {
            setupEngine(micFile: micFile, systemFile: systemFile)
        }

        guard let engine, let micPlayer, let systemPlayer else { return }

        if !engine.isRunning {
            try? engine.start()
        }

        micPlayer.play()
        systemPlayer.play()
        isPlaying = true
        startDisplayLink()
    }

    func pause() {
        micPlayer?.pause()
        systemPlayer?.pause()
        isPlaying = false
        stopDisplayLink()
    }

    func stop() {
        stopDisplayLink()
        engine?.stop()
        micPlayer = nil
        systemPlayer = nil
        engine = nil
        isPlaying = false
        currentTime = 0
    }

    func seek(to fraction: Double) {
        guard let micFile, let systemFile, let engine else { return }
        let wasPlaying = isPlaying

        micPlayer?.stop()
        systemPlayer?.stop()

        let targetFrame = AVAudioFramePosition(fraction * Double(micFile.length))

        let micRemaining = AVAudioFrameCount(max(0, Int64(micFile.length) - targetFrame))
        let sysRemaining = AVAudioFrameCount(max(0, Int64(systemFile.length) - targetFrame))

        if micRemaining > 0 {
            micPlayer?.scheduleSegment(micFile, startingFrame: targetFrame, frameCount: micRemaining, at: nil)
        }
        if sysRemaining > 0 {
            systemPlayer?.scheduleSegment(systemFile, startingFrame: targetFrame, frameCount: sysRemaining, at: nil)
        }

        startFrame = targetFrame
        currentTime = fraction * duration

        if wasPlaying {
            if !engine.isRunning { try? engine.start() }
            micPlayer?.play()
            systemPlayer?.play()
            isPlaying = true
            startDisplayLink()
        }
    }

    private func setupEngine(micFile: AVAudioFile, systemFile: AVAudioFile) {
        let engine = AVAudioEngine()
        let micNode = AVAudioPlayerNode()
        let sysNode = AVAudioPlayerNode()

        engine.attach(micNode)
        engine.attach(sysNode)

        // Pan: mic left, system right for stereo separation
        engine.connect(micNode, to: engine.mainMixerNode, format: micFile.processingFormat)
        engine.connect(sysNode, to: engine.mainMixerNode, format: systemFile.processingFormat)
        micNode.pan = -0.5
        sysNode.pan = 0.5

        micNode.scheduleFile(micFile, at: nil)
        sysNode.scheduleFile(systemFile, at: nil)

        self.engine = engine
        self.micPlayer = micNode
        self.systemPlayer = sysNode
        self.startFrame = 0
    }

    private func startDisplayLink() {
        stopDisplayLink()
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTime()
            }
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateTime() {
        guard let micPlayer, let micFile,
              let nodeTime = micPlayer.lastRenderTime,
              let playerTime = micPlayer.playerTime(forNodeTime: nodeTime) else { return }

        let sampleRate = micFile.processingFormat.sampleRate
        currentTime = Double(startFrame + playerTime.sampleTime) / sampleRate

        if currentTime >= duration {
            stop()
        }
    }

    // Extract amplitude envelope for waveform display
    private static func extractWaveform(from file: AVAudioFile, buckets: Int) -> [Float] {
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return Array(repeating: 0, count: buckets)
        }

        file.framePosition = 0
        try? file.read(into: buffer)

        guard let data = buffer.floatChannelData?[0] else {
            return Array(repeating: 0, count: buckets)
        }

        let samplesPerBucket = Int(frameCount) / buckets
        guard samplesPerBucket > 0 else { return Array(repeating: 0, count: buckets) }

        var result = [Float](repeating: 0, count: buckets)
        for i in 0..<buckets {
            var maxVal: Float = 0
            let start = i * samplesPerBucket
            let end = min(start + samplesPerBucket, Int(frameCount))
            for j in start..<end {
                let v = j < Int(frameCount) ? Swift.abs(data[j]) : 0
                if v > maxVal { maxVal = v }
            }
            result[i] = min(maxVal, 1.0)
        }

        // Normalize to peak so each track fills its vertical space
        let peak = result.max() ?? 0
        if peak > 0.001 {
            for i in 0..<buckets { result[i] /= peak }
        }

        return result
    }
}
