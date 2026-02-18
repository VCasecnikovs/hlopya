import SwiftUI
import AppKit
import Combine

/// Floating pill-shaped recording indicator.
final class RecordingNubPanel: NSPanel {
    private let viewModel: AppViewModel
    private var nubTimer: NubTimer?

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel

        // Wide enough for: dot + "00:00" + stop button + padding
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - 110
            let y = screen.visibleFrame.maxY - 56
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        let timer = NubTimer()
        self.nubTimer = timer
        let nubView = NubContent(timer: timer, onStop: { [weak viewModel] in
            Task { @MainActor in
                await viewModel?.stopRecording()
            }
        })
        let hostingView = NSHostingView(rootView: nubView)
        // Let the hosting view use its natural size - no constraints
        hostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 50)
        contentView = hostingView
    }

    override func close() {
        nubTimer?.stop()
        nubTimer = nil
        super.close()
    }
}

/// Timer that works reliably in NSPanel (Combine-based, not SwiftUI)
final class NubTimer: ObservableObject {
    @Published var formattedTime: String = "00:00"
    @Published var dotOpacity: Double = 1.0
    private var timer: Timer?
    private let startTime = Date()

    init() {
        // Fire every 0.05s for smooth pulse animation
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(self.startTime)
            let m = Int(elapsed) / 60
            let s = Int(elapsed) % 60
            // Smooth sine-wave pulse: period = 2 seconds
            let pulse = 0.3 + 0.7 * (0.5 + 0.5 * cos(elapsed * .pi))
            DispatchQueue.main.async {
                self.formattedTime = String(format: "%02d:%02d", m, s)
                self.dotOpacity = pulse
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

private struct NubContent: View {
    @ObservedObject var timer: NubTimer
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Pulsing red dot
            Circle()
                .fill(HlopColors.recordingDot)
                .frame(width: 8, height: 8)
                .opacity(timer.dotOpacity)

            // Timer - fixed width so it doesn't jump
            Text(timer.formattedTime)
                .font(HlopTypography.monoTimer)
                .foregroundStyle(.primary)
                .fixedSize()
                .accessibilityLabel("Recording time: \(timer.formattedTime)")

            // Stop button
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(HlopColors.recordingBadge.opacity(0.8))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
        }
        .padding(.horizontal, HlopSpacing.lg)
        .padding(.vertical, HlopSpacing.sm)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.red.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.red.opacity(0.25), lineWidth: 0.5)
                )
        }
        .shimmer(isActive: true)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .fixedSize()
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
