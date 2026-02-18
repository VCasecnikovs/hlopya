import SwiftUI
import FluidAudio

/// Vocabulary management page - shows loaded terms with option to load from folder
struct VocabularyView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var newTerm = ""
    @State private var searchText = ""
    @State private var isLoadingFolder = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vocabulary")
                        .font(.system(size: 20, weight: .bold))
                    Text("\(vm.vocabularyService.terms.count) terms loaded")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let path = vm.vocabularyService.loadedFromPath {
                        Text(path)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // Status badge
                if vm.vocabularyService.terms.isEmpty {
                    GlassBadge(text: "EMPTY", color: .secondary)
                } else if vm.isVocabConfigured {
                    GlassBadge(text: "ACTIVE", color: HlopColors.statusDone)
                } else {
                    GlassBadge(text: "LOADED", color: HlopColors.statusSTT)
                }
            }
            .padding(20)

            Divider()

            // Actions bar
            HStack(spacing: 8) {
                Button {
                    loadFromFolder()
                } label: {
                    Label("Load from Folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingFolder)

                if !vm.vocabularyService.terms.isEmpty {
                    Button {
                        vm.vocabularyService.clearAll()
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task { await vm.configureVocabulary() }
                    } label: {
                        Label(
                            vm.isVocabConfigured ? "Reconfigure CTC" : "Activate CTC",
                            systemImage: "waveform.badge.plus"
                        )
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(vm.isConfiguringVocab)
                }

                Spacer()

                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .frame(width: 150)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Error banner
            if let error = errorMessage {
                InlineErrorCard(
                    message: error,
                    onDismiss: { errorMessage = nil }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            // Progress
            if vm.isConfiguringVocab {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Configuring CTC rescoring...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Divider()

            // Add term row
            HStack(spacing: 8) {
                TextField("Add term...", text: $newTerm)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { addTerm() }

                Button("Add") { addTerm() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newTerm.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Term list
            if vm.vocabularyService.terms.isEmpty {
                EmptyStateView(
                    icon: "text.book.closed",
                    title: "No vocabulary loaded",
                    subtitle: "Load terms from a folder or add them manually"
                )
            } else {
                List(filteredTerms, id: \.text) { term in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term.text)
                                .font(.system(size: 13))
                            if let aliases = term.aliases, !aliases.isEmpty {
                                Text("aliases: \(aliases.joined(separator: ", "))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if let weight = term.weight {
                            Text("w:\(String(format: "%.0f", weight))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            vm.vocabularyService.removeTerm(term.text)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
            }
        }
    }

    private var filteredTerms: [CustomVocabularyTerm] {
        if searchText.isEmpty {
            return vm.vocabularyService.terms
        }
        let query = searchText.lowercased()
        return vm.vocabularyService.terms.filter { $0.text.lowercased().contains(query) }
    }

    private func addTerm() {
        let text = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        vm.vocabularyService.addTerm(text)
        newTerm = ""
    }

    private func loadFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to load vocabulary from (filenames become terms)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isLoadingFolder = true
            errorMessage = nil
            Task {
                do {
                    try await vm.vocabularyService.loadFromFolder(url: url)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isLoadingFolder = false
            }
        }
    }
}
