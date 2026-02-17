import SwiftUI

@main
struct HlopyaApp: App {
    @State private var viewModel = AppViewModel()
    @State private var nubPanel: RecordingNubPanel?

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 700, minHeight: 500)
                .onChange(of: viewModel.audioCapture.isRecording) { _, isRecording in
                    if isRecording {
                        showNub()
                    } else {
                        hideNub()
                    }
                }
        }
        .defaultSize(width: 900, height: 650)

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
                if let window = NSApp.windows.first(where: { $0.title == "Hlopya" || $0.isKeyWindow }) {
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

    private func showNub() {
        if nubPanel == nil {
            nubPanel = RecordingNubPanel(viewModel: viewModel)
        }
        nubPanel?.orderFront(nil)
    }

    private func hideNub() {
        nubPanel?.close()
        nubPanel = nil
    }
}
