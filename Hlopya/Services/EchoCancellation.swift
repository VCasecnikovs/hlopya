import Foundation
import Accelerate

/// Echo cancellation for speaker-mode recording.
///
/// When using speakers (not headphones), the mic picks up the remote person's voice
/// from the speakers. This creates duplicate content in both channels.
///
/// Algorithm:
/// 1. Estimate echo delay via cross-correlation peak
/// 2. Compute echo attenuation factor per frame
/// 3. Subtract scaled, delayed system signal from mic (spectral subtraction lite)
/// 4. Apply energy gating for remaining echo
enum EchoCancellation {

    /// Remove speaker bleed from mic audio using system audio as reference.
    static func removeEcho(
        micSamples: [Float],
        systemSamples: [Float],
        sampleRate: Int = 16000
    ) -> [Float] {
        let minLen = min(micSamples.count, systemSamples.count)
        guard minLen > sampleRate else { return Array(micSamples.prefix(minLen)) }

        var mic = Array(micSamples.prefix(minLen))
        let sys = Array(systemSamples.prefix(minLen))

        // Step 1: Estimate echo delay and strength
        let (delay, echoStrength) = estimateEchoDelay(mic: mic, sys: sys, sampleRate: sampleRate)
        print("[EchoCancellation] Echo delay: \(delay) samples (\(String(format: "%.1f", Double(delay) / Double(sampleRate) * 1000))ms), strength: \(String(format: "%.3f", echoStrength))")

        // Step 2: Subtract echo if significant
        if echoStrength > 0.05 {
            mic = subtractEcho(mic: mic, sys: sys, delay: delay, strength: echoStrength)
            print("[EchoCancellation] Echo subtracted (factor: \(String(format: "%.2f", echoStrength)))")
        }

        // Step 3: Energy gating to clean up residual
        let cleaned = applyEchoGating(mic: mic, sys: sys, sampleRate: sampleRate)
        return cleaned
    }

    // MARK: - Echo Delay Estimation

    /// Find the lag at which system audio best correlates with mic audio.
    /// Returns (delay in samples, correlation strength at that delay).
    private static func estimateEchoDelay(mic: [Float], sys: [Float], sampleRate: Int) -> (Int, Float) {
        // Search up to 200ms delay (typical speaker echo range)
        let maxDelay = sampleRate / 5 // 200ms
        let chunkSize = min(sampleRate * 5, mic.count) // Use 5 seconds
        let startOffset = mic.count / 3 // Start from middle

        guard startOffset + chunkSize <= mic.count else { return (0, 0) }

        let micChunk = Array(mic[startOffset..<(startOffset + chunkSize)])

        var bestLag = 0
        var bestCorr: Float = 0

        // Check correlations at different lags (every 4 samples for speed, ~0.25ms resolution)
        for lag in stride(from: 0, to: maxDelay, by: 4) {
            let sysStart = max(0, startOffset - lag)
            let sysEnd = min(sys.count, sysStart + chunkSize)
            guard sysEnd - sysStart == chunkSize else { continue }

            let sysChunk = Array(sys[sysStart..<sysEnd])

            // Compute correlation using vDSP
            var dot: Float = 0
            var micSq: Float = 0
            var sysSq: Float = 0
            vDSP_dotpr(micChunk, 1, sysChunk, 1, &dot, vDSP_Length(chunkSize))
            vDSP_dotpr(micChunk, 1, micChunk, 1, &micSq, vDSP_Length(chunkSize))
            vDSP_dotpr(sysChunk, 1, sysChunk, 1, &sysSq, vDSP_Length(chunkSize))

            let denom = sqrt(micSq * sysSq)
            guard denom > 0 else { continue }

            let corr = abs(dot / denom)
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }

        return (bestLag, bestCorr)
    }

    // MARK: - Echo Subtraction

    /// Subtract a scaled, delayed copy of system audio from mic.
    private static func subtractEcho(mic: [Float], sys: [Float], delay: Int, strength: Float) -> [Float] {
        var result = mic

        // Scale factor: how much system bleeds into mic
        // Use strength as base, but cap at 0.9 to avoid over-subtraction
        let scale = min(strength * 1.2, 0.9)

        let count = mic.count
        for i in 0..<count {
            let sysIdx = i - delay
            if sysIdx >= 0 && sysIdx < sys.count {
                result[i] -= sys[sysIdx] * scale
            }
        }

        return result
    }

    // MARK: - Energy Gating

    private static func applyEchoGating(mic: [Float], sys: [Float], sampleRate: Int) -> [Float] {
        let frameSize = Int(Double(sampleRate) * 0.020)
        let numFrames = mic.count / frameSize
        guard numFrames > 0 else { return mic }

        // Compute per-frame RMS
        var micRMS = [Float](repeating: 0, count: numFrames)
        var sysRMS = [Float](repeating: 0, count: numFrames)

        for i in 0..<numFrames {
            let start = i * frameSize
            mic.withUnsafeBufferPointer { ptr in
                var rms: Float = 0
                vDSP_rmsqv(ptr.baseAddress! + start, 1, &rms, vDSP_Length(frameSize))
                micRMS[i] = rms
            }
            sys.withUnsafeBufferPointer { ptr in
                var rms: Float = 0
                vDSP_rmsqv(ptr.baseAddress! + start, 1, &rms, vDSP_Length(frameSize))
                sysRMS[i] = rms
            }
        }

        // Thresholds
        let nonZeroSys = sysRMS.filter { $0 > 0.0005 }
        let sysMedian: Float = nonZeroSys.isEmpty ? 0.001 : {
            let sorted = nonZeroSys.sorted()
            return sorted[sorted.count / 2]
        }()
        let sysThreshold = max(sysMedian * 0.3, 0.002)

        let nonZeroMic = micRMS.filter { $0 > 0.0005 }
        let micMedian: Float = nonZeroMic.isEmpty ? 0.001 : {
            let sorted = nonZeroMic.sorted()
            return sorted[sorted.count / 2]
        }()

        // Compute gains - more permissive than before since echo was already subtracted
        var gains = [Float](repeating: 1.0, count: numFrames)
        var suppressedFrames = 0

        for i in 0..<numFrames {
            guard sysRMS[i] > sysThreshold else { continue }

            let micExcess = micRMS[i] / max(sysRMS[i], 1e-6)
            // After echo subtraction, mic should mostly have direct voice
            // Only suppress if mic is very quiet relative to system (pure echo residual)
            if micExcess > 1.5 && micRMS[i] > micMedian * 1.5 {
                // User is talking - keep it
                gains[i] = 1.0
            } else if micRMS[i] > micMedian * 0.5 {
                // Some content - partially attenuate
                gains[i] = 0.4
                suppressedFrames += 1
            } else {
                // Mostly echo residual - suppress
                gains[i] = 0.05
                suppressedFrames += 1
            }
        }

        // Smooth gains
        var smoothGains = gains
        for i in 1..<(numFrames - 1) {
            var window = [gains[i - 1], gains[i], gains[i + 1]]
            window.sort()
            smoothGains[i] = window[1]
        }

        // Apply gains with cross-fade
        var cleaned = mic
        let fadeLen = min(frameSize / 4, 80)

        for i in 0..<numFrames {
            let gain = smoothGains[i]
            guard gain < 1.0 else { continue }

            let start = i * frameSize
            let end = min(start + frameSize, cleaned.count)

            var g = gain
            cleaned.withUnsafeMutableBufferPointer { ptr in
                vDSP_vsmul(ptr.baseAddress! + start, 1, &g, ptr.baseAddress! + start, 1, vDSP_Length(end - start))
            }

            if i > 0 && abs(smoothGains[i - 1] - gain) > 0.1 {
                let prevGain = smoothGains[i - 1]
                cleaned.withUnsafeMutableBufferPointer { ptr in
                    let base = ptr.baseAddress! + start
                    for s in 0..<min(fadeLen, end - start) {
                        let t = Float(s) / Float(fadeLen)
                        let blendGain = prevGain * (1.0 - t) + gain * t
                        if gain > 0 {
                            base[s] = (base[s] / gain) * blendGain
                        } else {
                            base[s] = mic[start + s] * blendGain
                        }
                    }
                }
            }
        }

        let pct = Float(suppressedFrames) / Float(max(numFrames, 1)) * 100
        print("[EchoCancellation] \(suppressedFrames)/\(numFrames) frames gated (\(String(format: "%.0f", pct))%)")

        return cleaned
    }
}
