import ServiceManagement
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
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @State private var claudeCliPath: String? = nil
    @State private var isCheckingClaude = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String? = nil

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
                FolderPickerField(label: "Output Directory", path: $outputDir)
                Toggle("Auto-process after recording", isOn: $autoProcess)
                Text("Automatically transcribe and generate AI notes when recording stops")
                    .font(HlopTypography.footnote)
                    .foregroundStyle(.tertiary)
            }

            Section("Appearance") {
                Toggle("Show in Dock", isOn: $showDockIcon)
                    .disabled(showDockIcon && !showMenuBar)
                    .onChange(of: showDockIcon) { _, newValue in
                        NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                        // After flipping the policy (either direction), macOS
                        // deactivates the app. Re-raise the Settings window so
                        // the user doesn't feel like the app disappeared.
                        DispatchQueue.main.async {
                            NSApp.activate(ignoringOtherApps: true)
                            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
                        }
                    }
                Toggle("Show in menu bar", isOn: $showMenuBar)
                    .disabled(showMenuBar && !showDockIcon)
                Text("At least one of Dock or menu bar must stay visible so Hlopya remains accessible.")
                    .font(HlopTypography.footnote)
                    .foregroundStyle(.tertiary)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                            // Revert the toggle to reflect actual state.
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let err = launchAtLoginError {
                    Text(err)
                        .font(HlopTypography.footnote)
                        .foregroundStyle(.orange)
                } else if SMAppService.mainApp.status == .requiresApproval {
                    Text("Approve Hlopya in System Settings → General → Login Items to enable launch at login.")
                        .font(HlopTypography.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("Transcription") {
                HStack {
                    Text("STT Model")
                    Spacer()
                    if vm.transcriptionService.isModelLoaded {
                        HStack(spacing: HlopSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(HlopColors.statusDone)
                            Text("Parakeet v3 - loaded")
                                .foregroundStyle(.secondary)
                        }
                    } else if vm.transcriptionService.isModelCached {
                        HStack(spacing: HlopSpacing.xs) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.secondary)
                            Text("Parakeet v3 - on disk, not in memory")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not downloaded")
                            .foregroundStyle(.orange)
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
                FolderPickerField(label: "Vault Path", path: $obsidianVault)
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

/// TextField + "Browse..." button that opens a folder picker.
/// Selected paths are abbreviated to ~/ form when possible.
struct FolderPickerField: View {
    let label: String
    @Binding var path: String

    var body: some View {
        HStack(spacing: HlopSpacing.xs) {
            TextField(label, text: $path)
                .textFieldStyle(.roundedBorder)
            Button {
                pickFolder()
            } label: {
                Image(systemName: "folder")
            }
            .help("Choose folder")
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(label)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let expanded = (path as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }

        if panel.runModal() == .OK, let url = panel.url {
            path = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}
