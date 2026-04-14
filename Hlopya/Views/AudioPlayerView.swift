import SwiftUI

struct AudioPlayerView: View {
    @Environment(AppViewModel.self) private var vm
    let sessionId: String

    @State private var player = AudioPlayerService()
    @State private var isLoaded = false

    var body: some View {
        VStack(spacing: 6) {
            // Waveform tracks
            HStack(spacing: 8) {
                // Play/pause button
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Dual waveform + seek
                VStack(spacing: 2) {
                    WaveformTrack(
                        waveform: player.micWaveform,
                        progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                        color: HlopColors.statusMe,
                        label: "Me"
                    )
                    WaveformTrack(
                        waveform: player.systemWaveform,
                        progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                        color: HlopColors.statusThem,
                        label: "Them"
                    )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            // Need the geometry - use a simpler approach
                        }
                )
                .overlay(
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let fraction = max(0, min(1, location.x / geo.size.width))
                                player.seek(to: fraction)
                            }
                    }
                )

                // Time
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatTime(player.currentTime))
                        .font(.system(size: 11, design: .monospaced))
                    Text(formatTime(player.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 42)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .task(id: sessionId) {
            let dir = Session.recordingsDirectory.appendingPathComponent(sessionId)
            let micURL = dir.appendingPathComponent("mic.wav")
            let sysURL = dir.appendingPathComponent("system.wav")
            if FileManager.default.fileExists(atPath: micURL.path) &&
               FileManager.default.fileExists(atPath: sysURL.path) {
                player.load(micURL: micURL, systemURL: sysURL)
                isLoaded = true
            }
        }
        .onChange(of: sessionId) { _, _ in
            player.stop()
            isLoaded = false
        }
        .opacity(isLoaded ? 1 : 0)
        .frame(height: isLoaded ? nil : 0)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct WaveformTrack: View {
    let waveform: [Float]
    let progress: Double
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .leading)

            GeometryReader { geo in
                let barWidth = max(1, geo.size.width / CGFloat(max(waveform.count, 1)))
                let playedBars = Int(progress * Double(waveform.count))

                HStack(spacing: 0.5) {
                    ForEach(0..<waveform.count, id: \.self) { i in
                        let height = max(2, CGFloat(waveform[i]) * geo.size.height)
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(i < playedBars ? color : color.opacity(0.25))
                            .frame(width: max(barWidth - 0.5, 0.5), height: height)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: 20)
    }
}
