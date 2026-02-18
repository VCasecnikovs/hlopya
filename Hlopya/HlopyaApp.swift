import SwiftUI

@main
struct HlopyaApp: App {
    @State private var viewModel = AppViewModel()

    init() {
        // Workaround: suppress re-entrant constraint update assertion crash.
        // This is a known AppKit/SwiftUI bug where NSHostingView.updateAnimatedWindowSize
        // triggers setNeedsUpdateConstraints during a display cycle.
        // See: https://github.com/utmapp/UTM/issues/4691
        UserDefaults.standard.set(false, forKey: "NSWindowAssertWhenDisplayCycleLimitReached")
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 900, height: 650)
        .windowResizability(.contentSize)

        // Menu bar
        MenuBarExtra("Hlopya", systemImage: "mic.circle.fill") {
            if viewModel.audioCapture.isRecording {
                Text("Recording: \(viewModel.audioCapture.formattedTime)")
                    .font(.caption)
                Divider()
                Button("Stop Recording") {
                    Task { await viewModel.stopRecording() }
                }
            } else {
                Button("Start Recording") {
                    Task { await viewModel.startRecording() }
                }
            }
            Divider()
            Button("Show Window") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Quit") {
                if viewModel.audioCapture.isRecording {
                    Task {
                        await viewModel.stopRecording()
                        NSApp.terminate(nil)
                    }
                } else {
                    NSApp.terminate(nil)
                }
            }
        }

        // Settings
        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
