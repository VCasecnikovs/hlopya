import SwiftUI

/// Main window: NavigationSplitView with sidebar (sessions) + detail (transcript/notes)
struct ContentView: View {
    @Environment(AppViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm

        NavigationSplitView {
            SessionListView()
        } detail: {
            if vm.selectedSessionId != nil {
                SessionDetailView()
            } else {
                emptyState
            }
        }
        .navigationSplitViewStyle(.balanced)
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
