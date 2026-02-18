import SwiftUI

@main
struct HlopyaApp: App {
    @State private var viewModel = AppViewModel()
    @AppStorage("setupComplete") private var setupComplete = false

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
            if setupComplete {
                ContentView()
                    .environment(viewModel)
            } else {
                SetupWizardView()
                    .environment(viewModel)
            }
        }
        .defaultSize(width: 900, height: 650)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button(viewModel.audioCapture.isRecording ? "Stop Recording" : "Start Recording") {
                    Task { await viewModel.toggleRecording() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        // Menu bar
        MenuBarExtra("Hlopya", systemImage: "mic.circle.fill") {
            if viewModel.audioCapture.isRecording {
                Text("Recording: \(viewModel.audioCapture.formattedTime)")
                    .font(.caption)
                Divider()
                Button("Stop Recording") {
                    Task { await viewModel.stopRecording() }
                }
                .keyboardShortcut("r", modifiers: .command)
            } else {
                Button("Start Recording") {
                    Task { await viewModel.startRecording() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            Divider()
            Button("Show Window") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut("o", modifiers: .command)
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
            .keyboardShortcut("q", modifiers: .command)
        }

        // Settings
        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
