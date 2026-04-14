import Foundation
import Accelerate

/// Offline echo suppression using spectral gating with delay compensation.
///
/// When using speakers, the mic picks up the other person's voice from the speakers.
/// We suppress these echo portions by comparing mic energy vs system energy per frame:
/// - System loud, mic similar → mostly echo → suppress
/// - Mic much louder than system → user speaking → keep
/// - Both active → partial suppression based on energy ratio
enum EchoCancellation {

    static func removeEcho(
        micSamples: [Float],
        systemSamples: [Float],
        sampleRate: Int = 16000
    ) -> [Float] {
        let minLen = min(micSamples.count, systemSamples.count)
        guard minLen > sampleRate else { return Array(micSamples.prefix(minLen)) }

        var mic = Array(micSamples.prefix(minLen))
        let sys = Array(systemSamples.prefix(minLen))

        // Check if system audio has content
        var sysRMS: Float = 0
        vDSP_rmsqv(sys, 1, &sysRMS, vDSP_Length(minLen))
        if sysRMS < 0.001 {
            NSLog("[EchoCancellation] System audio silent, skipping")
            return mic
        }

        // Step 1: Find echo delay via cross-correlation
        let delay = findEchoDelay(mic: mic, sys: sys, sampleRate: sampleRate)
        NSLog("[EchoCancellation] Echo delay: %d samples (%.1f ms)", delay, Double(delay) / Double(sampleRate) * 1000)

        // Step 2: Build aligned system track
        let alignedSys: [Float]
        if delay > 0 {
            alignedSys = Array(repeating: Float(0), count: delay) + Array(sys.prefix(minLen - delay))
        } else {
            alignedSys = sys
        }

        // Step 3: Compute per-frame energy and apply spectral gating
        let frameSize = sampleRate / 50  // 20ms frames
        let numFrames = minLen / frameSize
        guard numFrames > 1 else { return mic }

        // Compute frame energies
        var micEnergy = [Float](repeating: 0, count: numFrames)
        var sysEnergy = [Float](repeating: 0, count: numFrames)

        for i in 0..<numFrames {
            let start = i * frameSize
            mic.withUnsafeBufferPointer { ptr in
                vDSP_svesq(ptr.baseAddress! + start, 1, &micEnergy[i], vDSP_Length(frameSize))
            }
            alignedSys.withUnsafeBufferPointer { ptr in
                vDSP_svesq(ptr.baseAddress! + start, 1, &sysEnergy[i], vDSP_Length(frameSize))
            }
        }

        // Estimate echo-to-mic attenuation from frames where system is active
        let echoScale = estimateEchoScale(micEnergy: micEnergy, sysEnergy: sysEnergy)
        NSLog("[EchoCancellation] Estimated echo scale: %.3f", echoScale)

        // Compute suppression gains per frame
        var gains = [Float](repeating: 1.0, count: numFrames)
        let floor: Float = 0.08  // Don't suppress below this to avoid artifacts

        for i in 0..<numFrames {
            let sysE = sysEnergy[i] * echoScale * echoScale
            let micE = micEnergy[i]

            guard sysE > 1e-8 else { continue }

            // Estimated echo energy in mic
            let echoRatio = sysE / max(micE, 1e-10)

            if echoRatio > 0.8 {
                // Mic is mostly echo - strong suppression
                gains[i] = floor
            } else if echoRatio > 0.2 {
                // Mix of voice + echo - proportional suppression
                // Wiener-style: keep the portion that isn't echo
                gains[i] = max(floor, 1.0 - echoRatio)
            }
            // else: mic >> system echo, user is speaking, keep full gain
        }

        // Smooth gains to avoid clicking (median filter + exponential smoothing)
        var smoothed = gains
        // Median filter (window=3)
        for i in 1..<(numFrames - 1) {
            var w = [gains[i - 1], gains[i], gains[i + 1]]
            w.sort()
            smoothed[i] = w[1]
        }
        // Exponential smoothing
        let alpha: Float = 0.3
        for i in 1..<numFrames {
            smoothed[i] = alpha * smoothed[i] + (1 - alpha) * smoothed[i - 1]
        }

        // Apply gains with per-sample crossfade between frames
        let fadeLen = frameSize / 4
        for i in 0..<numFrames {
            let start = i * frameSize
            let end = min(start + frameSize, minLen)
            var gain = smoothed[i]
            guard gain < 1.0 else { continue }

            // Apply gain to frame
            mic.withUnsafeMutableBufferPointer { ptr in
                vDSP_vsmul(ptr.baseAddress! + start, 1, &gain, ptr.baseAddress! + start, 1, vDSP_Length(end - start))
            }

            // Crossfade at boundary to prevent clicks
            if i > 0 && abs(smoothed[i - 1] - smoothed[i]) > 0.1 {
                let prevGain = smoothed[i - 1]
                for s in 0..<min(fadeLen, end - start) {
                    let t = Float(s) / Float(fadeLen)
                    let blend = prevGain * (1 - t) + gain * t
                    // Undo the gain we just applied, reapply blended
                    if gain > 0 {
                        mic[start + s] = (mic[start + s] / gain) * blend
                    }
                }
            }
        }

        // Report
        let suppressedCount = gains.filter { $0 < 0.5 }.count
        NSLog("[EchoCancellation] Suppressed %d/%d frames (%.0f%%)",
              suppressedCount, numFrames, Float(suppressedCount) / Float(numFrames) * 100)

        return mic
    }

    // MARK: - Echo Delay Estimation

    /// Cross-correlate system audio with mic to find the speaker-to-mic delay.
    private static func findEchoDelay(mic: [Float], sys: [Float], sampleRate: Int) -> Int {
        let maxDelay = sampleRate / 5  // Search up to 200ms
        // Use a chunk from the middle of the recording where there's likely content
        let chunkLen = min(sampleRate * 3, mic.count / 2)
        let offset = mic.count / 3

        guard offset + chunkLen <= mic.count, offset + chunkLen + maxDelay <= sys.count else { return 0 }

        var bestLag = 0
        var bestCorr: Float = 0

        let micChunk = Array(mic[offset..<(offset + chunkLen)])

        for lag in stride(from: 0, to: maxDelay, by: 2) {
            let sysStart = offset + lag
            guard sysStart + chunkLen <= sys.count else { break }

            var dot: Float = 0
            var micSq: Float = 0
            var sysSq: Float = 0

            micChunk.withUnsafeBufferPointer { mPtr in
                sys.withUnsafeBufferPointer { sPtr in
                    let sBase = sPtr.baseAddress! + sysStart
                    vDSP_dotpr(mPtr.baseAddress!, 1, sBase, 1, &dot, vDSP_Length(chunkLen))
                    vDSP_dotpr(mPtr.baseAddress!, 1, mPtr.baseAddress!, 1, &micSq, vDSP_Length(chunkLen))
                    vDSP_dotpr(sBase, 1, sBase, 1, &sysSq, vDSP_Length(chunkLen))
                }
            }

            let denom = sqrt(micSq * sysSq)
            guard denom > 0 else { continue }

            let corr = abs(dot / denom)
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }

        return bestLag
    }

    // MARK: - Echo Scale Estimation

    /// Estimate how much of the system audio leaks into the mic.
    /// Uses frames where system is active but mic energy is low (pure echo).
    private static func estimateEchoScale(micEnergy: [Float], sysEnergy: [Float]) -> Float {
        // Find frames where system is active
        let sysThreshold: Float = {
            let sorted = sysEnergy.filter { $0 > 0 }.sorted()
            guard !sorted.isEmpty else { return 0 }
            return sorted[sorted.count * 3 / 4]  // 75th percentile
        }()

        guard sysThreshold > 0 else { return 0 }

        // Collect mic/sys energy ratios for active system frames
        var ratios: [Float] = []
        for i in 0..<micEnergy.count {
            if sysEnergy[i] > sysThreshold * 0.5 {
                let ratio = sqrt(micEnergy[i] / max(sysEnergy[i], 1e-10))
                ratios.append(ratio)
            }
        }

        guard !ratios.isEmpty else { return 0.3 }

        // Use 25th percentile as echo scale (lower ratios = purer echo)
        ratios.sort()
        let echoScale = ratios[ratios.count / 4]

        return min(echoScale, 1.0)
    }
}
