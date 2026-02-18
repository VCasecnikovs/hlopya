import Foundation

/// Writes PCM audio data to a WAV file.
/// Ported from audiocap/Sources/main.swift - nearly identical logic.
final class WAVWriter {
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
        let bps: UInt16 = 2  // 16-bit PCM
        let ba = UInt16(channels) * bps
        let br = UInt32(sampleRate) * UInt32(ba)

        h.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        withUnsafeBytes(of: (dataSize + 36).littleEndian) { h.append(contentsOf: $0) }
        h.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        h.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        withUnsafeBytes(of: UInt32(16).littleEndian) { h.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { h.append(contentsOf: $0) }  // PCM
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
        writeHeader()  // Rewrite with final size
        fileHandle.closeFile()
        let dur = Double(dataSize) / Double(UInt32(sampleRate) * UInt32(channels) * 2)
        print("[WAVWriter] Saved: \(filePath) (\(String(format: "%.1f", dur))s)")
    }

    var durationSeconds: Double {
        Double(dataSize) / Double(UInt32(sampleRate) * UInt32(channels) * 2)
    }
}
