import SwiftUI

/// App preferences
struct SettingsView: View {
    @Environment(AppViewModel.self) private var vm

    @AppStorage("outputDir") private var outputDir = "~/recordings"
    @AppStorage("autoProcess") private var autoProcess = true
    @AppStorage("claudeModel") private var claudeModel = "claude-sonnet-4-5-20250929"
    @AppStorage("obsidianVault") private var obsidianVault = "~/Documents/MyBrain"

    var body: some View {
        Form {
            Section("Recording") {
                TextField("Output Directory", text: $outputDir)
                    .textFieldStyle(.roundedBorder)
                Toggle("Auto-process after recording", isOn: $autoProcess)
            }

            Section("Transcription") {
                HStack {
                    Text("STT Model")
                    Spacer()
                    Text("Parakeet v3 (CoreML)")
                        .foregroundStyle(.secondary)
                }

                if vm.transcriptionService.isModelLoaded {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Model loaded")
                    }
                } else {
                    Button("Download Model (~400MB)") {
                        Task {
                            try? await vm.transcriptionService.loadModel()
                        }
                    }
                    .disabled(vm.transcriptionService.isDownloading)

                    if vm.transcriptionService.isDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("Notes") {
                Picker("Claude Model", selection: $claudeModel) {
                    Text("Sonnet 4.5").tag("claude-sonnet-4-5-20250929")
                    Text("Opus 4").tag("claude-opus-4-20250514")
                    Text("Haiku 3.5").tag("claude-3-5-haiku-20241022")
                }
            }

            Section("Obsidian") {
                TextField("Vault Path", text: $obsidianVault)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
    }
}
