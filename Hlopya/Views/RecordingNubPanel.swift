import SwiftUI
import AppKit

/// Floating 56x56 recording indicator panel.
/// Uses NSPanel for always-on-top, no-activation behavior.
final class RecordingNubPanel: NSPanel {
    private let viewModel: AppViewModel

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 56, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true

        // Position: right side, upper third
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - 72
            let y = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.3
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        let hostingView = NSHostingView(rootView: NubContent(viewModel: viewModel, panel: self))
        contentView = hostingView
    }
}

/// SwiftUI content for the floating nub
private struct NubContent: View {
    let viewModel: AppViewModel
    let panel: RecordingNubPanel

    var body: some View {
        VStack(spacing: 2) {
            // Audio bars animation
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    AudioBar(delay: Double(i) * 0.1)
                }
            }
            .frame(height: 16)

            // Timer
            Text(viewModel.audioCapture.formattedTime)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 48, height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.9))
                .shadow(color: .red.opacity(0.4), radius: 6, y: 2)
        )
        .modifier(BreathingAnimation())
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

/// Single animated audio bar
private struct AudioBar: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .frame(width: 3, height: isAnimating ? 8 : 14)
            .animation(
                .easeInOut(duration: 0.8)
                .repeatForever()
                .delay(delay),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

/// Subtle scale breathing animation
private struct BreathingAnimation: ViewModifier {
    @State private var isBreathing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isBreathing ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 2.0).repeatForever(), value: isBreathing)
            .onAppear { isBreathing = true }
    }
}
