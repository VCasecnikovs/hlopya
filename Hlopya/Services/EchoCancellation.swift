import Foundation
import Accelerate

/// Aggressive energy-gated echo cancellation using Accelerate vDSP.
///
/// Algorithm:
/// 1. Compute per-frame RMS energy for mic and system channels (20ms frames)
/// 2. Calculate adaptive system threshold (median * 0.3)
/// 3. When system audio is active: hard-gate mic to near-zero UNLESS mic is
///    significantly louder than system (local person talking over remote)
/// 4. Apply cross-fade at frame boundaries to avoid clicks
enum EchoCancellation {

    /// Remove speaker bleed from mic audio using system audio as reference.
    static func removeEcho(
        micSamples: [Float],
        systemSamples: [Float],
        sampleRate: Int = 16000
    ) -> [Float] {
        let minLen = min(micSamples.count, systemSamples.count)
        let mic = Array(micSamples.prefix(minLen))
        let sys = Array(systemSamples.prefix(minLen))

        // 20ms frames (shorter = more precise gating)
        let frameSize = Int(Double(sampleRate) * 0.020)
        let numFrames = minLen / frameSize
        guard numFrames > 0 else { return mic }

        // Compute per-frame RMS energy using vDSP
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

        // Adaptive threshold: system "active" when RMS > median * 0.3
        let nonZeroSys = sysRMS.filter { $0 > 0.0005 }
        let sysMedian: Float
        if nonZeroSys.isEmpty {
            sysMedian = 0.001
        } else {
            let sorted = nonZeroSys.sorted()
            sysMedian = sorted[sorted.count / 2]
        }
        let sysThreshold = max(sysMedian * 0.3, 0.002)

        // Also compute mic noise floor for "local speaker is talking" detection
        let nonZeroMic = micRMS.filter { $0 > 0.0005 }
        let micMedian: Float
        if nonZeroMic.isEmpty {
            micMedian = 0.001
        } else {
            let sorted = nonZeroMic.sorted()
            micMedian = sorted[sorted.count / 2]
        }

        // Compute per-frame gain
        // Strategy: when system is active, suppress mic HARD (0.0)
        // Exception: if mic is significantly louder than what echo would produce,
        // the local person is actually speaking - let it through
        var gains = [Float](repeating: 1.0, count: numFrames)
        var suppressedFrames = 0

        // Echo ratio threshold: mic must be this many times louder than system
        // to be considered "local person talking over echo"
        let localSpeakerRatio: Float = 2.5

        for i in 0..<numFrames {
            guard sysRMS[i] > sysThreshold else { continue }

            // Is the local person also speaking? Only if mic is MUCH louder than system
            let micExcess = micRMS[i] / max(sysRMS[i], 1e-6)
            if micExcess > localSpeakerRatio && micRMS[i] > micMedian * 2.0 {
                // Both talking - keep mic but attenuate echo component
                gains[i] = 0.5
            } else {
                // System only - hard suppress mic (echo)
                gains[i] = 0.0
                suppressedFrames += 1
            }
        }

        // Smooth gains to avoid clicks (apply 3-frame median filter)
        var smoothGains = gains
        for i in 1..<(numFrames - 1) {
            var window = [gains[i - 1], gains[i], gains[i + 1]]
            window.sort()
            smoothGains[i] = window[1]
        }

        // Apply gains with per-sample cross-fade within frames
        var cleaned = mic
        let fadeLen = min(frameSize / 4, 80) // ~5ms fade

        for i in 0..<numFrames {
            let gain = smoothGains[i]
            guard gain < 1.0 else { continue }

            let start = i * frameSize
            let end = min(start + frameSize, cleaned.count)

            // Apply gain to frame center
            var g = gain
            cleaned.withUnsafeMutableBufferPointer { ptr in
                vDSP_vsmul(ptr.baseAddress! + start, 1, &g, ptr.baseAddress! + start, 1, vDSP_Length(end - start))
            }

            // Cross-fade at boundaries if neighboring frame has different gain
            if i > 0 && abs(smoothGains[i - 1] - gain) > 0.1 {
                let prevGain = smoothGains[i - 1]
                cleaned.withUnsafeMutableBufferPointer { ptr in
                    let base = ptr.baseAddress! + start
                    for s in 0..<min(fadeLen, end - start) {
                        let t = Float(s) / Float(fadeLen)
                        let blendGain = prevGain * (1.0 - t) + gain * t
                        // Undo the hard gain and reapply blended
                        if gain > 0 {
                            base[s] = (base[s] / gain) * blendGain
                        } else {
                            // Was zeroed - reconstruct from original mic
                            base[s] = mic[start + s] * blendGain
                        }
                    }
                }
            }
        }

        let pct = Float(suppressedFrames) / Float(max(numFrames, 1)) * 100
        print("[EchoCancellation] \(suppressedFrames)/\(numFrames) frames suppressed (\(String(format: "%.0f", pct))%)")
        print("[EchoCancellation] Sys threshold: \(String(format: "%.4f", sysThreshold)), mic median: \(String(format: "%.4f", micMedian))")

        return cleaned
    }
}
