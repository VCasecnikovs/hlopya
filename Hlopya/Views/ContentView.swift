import SwiftUI

/// Main window: manual HStack layout (sidebar + detail)
/// Using HStack instead of NavigationSplitView to avoid constraint crash
/// during recording state changes (macOS SwiftUI bug).
///
/// Keyboard shortcuts (defined in HlopyaApp.swift):
///   ⌘R - Toggle recording (start/stop)
///   ⌘1 / ⌘2 - Switch detail tabs (requires SessionDetailView refactor)
struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm

        HStack(spacing: 0) {
            SessionListView()
                .frame(width: HlopSpacing.sidebarWidth)

            Divider()

            if vm.selectedSessionId != nil {
                SessionDetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 800, minHeight: 500)
        .alert("Recording Error", isPresented: Binding(
            get: { vm.audioCapture.lastError != nil },
            set: { if !$0 { vm.audioCapture.lastError = nil } }
        )) {
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                vm.audioCapture.lastError = nil
            }
            Button("OK", role: .cancel) {
                vm.audioCapture.lastError = nil
            }
        } message: {
            Text(vm.audioCapture.lastError ?? "Unknown error")
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "mic.fill",
            title: "Record a meeting to get started",
            subtitle: "Capture audio and get automatic transcription",
            buttonTitle: vm.audioCapture.isRecording ? "Stop Recording" : "Start Recording",
            action: {
                Task { await vm.toggleRecording() }
            }
        )
        .accessibilityLabel(
            vm.audioCapture.isRecording
                ? "Stop recording"
                : "Start recording a new meeting"
        )
    }
}
