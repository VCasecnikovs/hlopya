import SwiftUI

/// Main window: manual HStack layout (sidebar + detail)
/// Using HStack instead of NavigationSplitView to avoid constraint crash
/// during recording state changes (macOS SwiftUI bug).
struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm

        HStack(spacing: 0) {
            SessionListView()
                .frame(width: 260)

            Divider()

            if vm.selectedSessionId != nil {
                SessionDetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        }
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
        VStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Record a meeting to get started")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
