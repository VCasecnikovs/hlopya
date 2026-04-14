import SwiftUI

/// App preferences
struct SettingsView: View {
    @Environment(AppViewModel.self) private var vm

    @AppStorage("outputDir") private var outputDir = "~/recordings"
    @AppStorage("autoProcess") private var autoProcess = true
    @AppStorage("userName") private var userName = ""
    @AppStorage("claudeModel") private var claudeModel = "sonnet"
    @AppStorage("obsidianVault") private var obsidianVault = "~/Documents/MyBrain"
    @AppStorage("setupComplete") private var setupComplete = false
    @State private var claudeCliPath: String? = nil
    @State private var isCheckingClaude = true

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Your Name", text: $userName, prompt: Text("e.g. Vadim"))
                    .textFieldStyle(.roundedBorder)
                Text("Used in transcripts as \"Me (your name)\" and passed to AI notes")
                    .font(HlopTypography.footnote)
                    .foregroundStyle(.tertiary)
            }

            Section("Recording") {
                TextField("Output Directory", text: $outputDir)
                    .textFieldStyle(.roundedBorder)
                Toggle("Auto-process after recording", isOn: $autoProcess)
                Text("Automatically transcribe and generate AI notes when recording stops")
                    .font(HlopTypography.footnote)
                    .foregroundStyle(.tertiary)
            }

            Section("Transcription") {
                HStack {
                    Text("STT Model")
                    Spacer()
                    if vm.transcriptionService.isModelLoaded {
                        HStack(spacing: HlopSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(HlopColors.statusDone)
                            Text("Parakeet v3 (CoreML)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not downloaded")
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("Check System page in sidebar for download & health status")
                    .font(HlopTypography.footnote)
                    .foregroundStyle(.tertiary)
            }

            Section("Notes") {
                HStack {
                    Text("Claude CLI")
                    Spacer()
                    if isCheckingClaude {
                        ProgressView()
                            .controlSize(.small)
                    } else if let path = claudeCliPath {
                        HStack(spacing: HlopSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(HlopColors.statusDone)
                            Text(path)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        HStack(spacing: HlopSpacing.xs) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Not found")
                                .foregroundStyle(.secondary)
                            Button("Install") {
                                NSWorkspace.shared.open(URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!)
                            }
                            .controlSize(.small)
                        }
                    }
                }
                if claudeCliPath == nil && !isCheckingClaude {
                    Text("Required for AI note generation. Install Claude Code CLI, then reopen Settings.")
                        .font(HlopTypography.footnote)
                        .foregroundStyle(.orange)
                }
                Picker("Claude Model", selection: $claudeModel) {
                    Text("Sonnet 4.6").tag("sonnet")
                    Text("Opus 4.6").tag("opus")
                    Text("Haiku 4.5").tag("haiku")
                }
                Text("Model used for generating meeting notes and summaries")
                    .font(HlopTypography.footnote)
                    .foregroundStyle(.tertiary)
            }

            Section("Obsidian") {
                TextField("Vault Path", text: $obsidianVault)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                Button("Run Setup Wizard Again") {
                    setupComplete = false
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
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
}
