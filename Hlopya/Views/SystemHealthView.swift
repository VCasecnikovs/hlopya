import SwiftUI

/// System health & configuration page - model status, downloads, diagnostics
struct SystemHealthView: View {
    @Environment(AppViewModel.self) private var vm
    @State private var claudeCliPath: String? = nil
    @State private var isCheckingClaude = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("System")
                    .font(.system(size: 22, weight: .bold))
                    .padding(.bottom, 4)

                // STT Model
                sttModelCard

                // Vocabulary CTC
                vocabularyCTCCard

                // Claude CLI
                claudeCliCard

                // Recording
                recordingCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            isCheckingClaude = true
            let path = await Task.detached {
                let p = NoteGenerationService.findClaudeCLI()
                return (p != "claude" && FileManager.default.isExecutableFile(atPath: p)) ? p : nil
            }.value
            claudeCliPath = path
            isCheckingClaude = false
        }
    }

    // MARK: - STT Model

    private var sttModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Speech-to-Text", systemImage: "waveform")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                statusDot(ok: vm.transcriptionService.isModelLoaded || vm.transcriptionService.isModelCached)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Parakeet v3 (CoreML)")
                        .font(.system(size: 13, weight: .medium))

                    if vm.transcriptionService.isModelLoaded {
                        Text("Loaded in memory")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else if vm.transcriptionService.isDownloading {
                        Text("Downloading...")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else if vm.transcriptionService.isModelCached {
                        Text("Downloaded, not in memory (loads automatically)")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not downloaded")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if vm.transcriptionService.isModelLoaded {
                    Button("Unload") {
                        vm.transcriptionService.unloadModel()
                        vm.isVocabConfigured = false
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)

                    GlassBadge(text: "OK", color: HlopColors.statusDone)
                } else if vm.transcriptionService.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Load") {
                        Task { try? await vm.transcriptionService.loadModel() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Vocabulary CTC

    private var vocabularyCTCCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Vocabulary Boosting", systemImage: "text.book.closed")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                statusDot(ok: vm.isVocabConfigured)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CTC Rescoring")
                        .font(.system(size: 13, weight: .medium))

                    if vm.isVocabConfigured {
                        Text("\(vm.vocabularyService.terms.count) terms active")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else if vm.vocabularyService.terms.isEmpty {
                        Text("No vocabulary loaded")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("\(vm.vocabularyService.terms.count) terms loaded, not activated")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if vm.isVocabConfigured {
                    GlassBadge(text: "ACTIVE", color: HlopColors.statusDone)
                } else if vm.isConfiguringVocab {
                    ProgressView()
                        .controlSize(.small)
                } else if !vm.vocabularyService.terms.isEmpty {
                    Button("Activate") {
                        Task { await vm.configureVocabulary() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                } else {
                    GlassBadge(text: "EMPTY", color: .secondary)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Claude CLI

    private var claudeCliCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Notes", systemImage: "brain")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                if isCheckingClaude {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 10, height: 10)
                } else {
                    statusDot(ok: claudeCliPath != nil)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code CLI")
                        .font(.system(size: 13, weight: .medium))

                    if isCheckingClaude {
                        Text("Checking...")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.secondary)
                    } else if let path = claudeCliPath {
                        Text(path)
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Not installed - AI notes disabled")
                            .font(HlopTypography.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if isCheckingClaude {
                    EmptyView()
                } else if claudeCliPath != nil {
                    GlassBadge(text: "OK", color: HlopColors.statusDone)
                } else {
                    Button("Install") {
                        NSWorkspace.shared.open(URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Recording

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio Capture", systemImage: "mic")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                statusDot(ok: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mic + System Audio")
                        .font(.system(size: 13, weight: .medium))

                    Text(vm.audioCapture.isRecording ? "Recording..." : "Idle")
                        .font(HlopTypography.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(vm.sessionManager.sessions.count) sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Helpers

    private func statusDot(ok: Bool) -> some View {
        Circle()
            .fill(ok ? Color.green : Color.orange)
            .frame(width: 10, height: 10)
    }
}
