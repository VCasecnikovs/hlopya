import Foundation
import Accelerate

/// Energy-gated echo cancellation using Accelerate vDSP.
/// Port of the Python numpy RMS algorithm from transcriber.py.
///
/// Algorithm:
/// 1. Compute per-frame RMS energy for mic and system channels (30ms frames)
/// 2. Calculate adaptive system threshold (median * 0.5, min 0.003)
/// 3. When system audio is active and louder than mic, apply soft attenuation
enum EchoCancellation {

    /// Remove speaker bleed from mic audio using system audio as reference.
    /// - Parameters:
    ///   - micSamples: Mic channel as Float32 samples
    ///   - systemSamples: System channel as Float32 samples
    ///   - sampleRate: Audio sample rate (default 16000)
    /// - Returns: Cleaned mic samples with echo removed
    static func removeEcho(
        micSamples: [Float],
        systemSamples: [Float],
        sampleRate: Int = 16000
    ) -> [Float] {
        // Align lengths
        let minLen = min(micSamples.count, systemSamples.count)
        let mic = Array(micSamples.prefix(minLen))
        let sys = Array(systemSamples.prefix(minLen))

        // 30ms frames for smooth gating
        let frameSize = Int(Double(sampleRate) * 0.030)
        let numFrames = minLen / frameSize
        guard numFrames > 0 else { return mic }

        // Compute per-frame RMS energy using vDSP
        var micRMS = [Float](repeating: 0, count: numFrames)
        var sysRMS = [Float](repeating: 0, count: numFrames)

        for i in 0..<numFrames {
            let start = i * frameSize
            mic.withUnsafeBufferPointer { ptr in
                let base = ptr.baseAddress! + start
                var rms: Float = 0
                vDSP_rmsqv(base, 1, &rms, vDSP_Length(frameSize))
                micRMS[i] = rms
            }
            sys.withUnsafeBufferPointer { ptr in
                let base = ptr.baseAddress! + start
                var rms: Float = 0
                vDSP_rmsqv(base, 1, &rms, vDSP_Length(frameSize))
                sysRMS[i] = rms
            }
        }

        // Adaptive threshold: system "active" when RMS > median * 0.5
        let nonZeroSys = sysRMS.filter { $0 > 0 }
        let sysMedian: Float
        if nonZeroSys.isEmpty {
            sysMedian = 0.001
        } else {
            let sorted = nonZeroSys.sorted()
            sysMedian = sorted[sorted.count / 2]
        }
        let sysThreshold = max(sysMedian * 0.5, 0.003)

        // Apply soft gate
        var cleaned = mic
        var suppressedFrames = 0

        for i in 0..<numFrames {
            guard sysRMS[i] > sysThreshold else { continue }

            let ratio = sysRMS[i] / max(micRMS[i], 1e-6)
            guard ratio > 0.3 else { continue }

            // Soft attenuation: stronger when system is louder
            let attenuation = max(0.05, 1.0 - min(ratio * 0.8, 0.95))
            let start = i * frameSize
            let end = min(start + frameSize, cleaned.count)

            // vDSP scalar multiply for the frame
            var att = attenuation
            cleaned.withUnsafeMutableBufferPointer { ptr in
                vDSP_vsmul(ptr.baseAddress! + start, 1, &att, ptr.baseAddress! + start, 1, vDSP_Length(end - start))
            }
            suppressedFrames += 1
        }

        let pct = Float(suppressedFrames) / Float(max(numFrames, 1)) * 100
        print("[EchoCancellation] \(suppressedFrames)/\(numFrames) frames suppressed (\(String(format: "%.0f", pct))%)")
        print("[EchoCancellation] Threshold: \(String(format: "%.4f", sysThreshold)), median RMS: \(String(format: "%.4f", sysMedian))")

        return cleaned
    }
}
