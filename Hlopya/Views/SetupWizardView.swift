import SwiftUI
import AVFoundation

/// First-launch setup wizard - checks permissions, model, and Claude CLI.
struct SetupWizardView: View {
    @Environment(AppViewModel.self) private var vm
    @AppStorage("setupComplete") private var setupComplete = false

    @State private var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var claudePath: String? = nil
    @State private var isCheckingClaude = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "mic.badge.xmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Welcome to Hlopya")
                    .font(.title.bold())
                Text("Meeting recorder & note-taker")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // Steps
            VStack(spacing: 16) {
                permissionsStep
                modelStep
                claudeStep
            }
            .padding(.horizontal, 40)

            Spacer()

            // Get Started
            Button {
                setupComplete = true
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canProceed)
            .padding(.horizontal, 40)
            .padding(.bottom, 28)

            if !canProceed {
                Text("Grant microphone permission to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: 520, height: 560)
        .task {
            checkClaude()
        }
    }

    private var canProceed: Bool {
        micStatus == .authorized
    }

    // MARK: - Step 1: Permissions

    private var permissionsStep: some View {
        StepCard(number: 1, title: "Permissions") {
            // Microphone
            HStack {
                statusIcon(for: micStatus == .authorized)
                Text("Microphone")
                Spacer()
                if micStatus == .authorized {
                    Text("Granted").foregroundStyle(.green)
                } else if micStatus == .denied || micStatus == .restricted {
                    Button("Open System Settings") {
                        openPrivacySettings()
                    }
                    .controlSize(.small)
                } else {
                    Button("Grant") {
                        requestMicPermission()
                    }
                    .controlSize(.small)
                }
            }

            // System Audio
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("System Audio")
                Spacer()
                Text("Prompted on first record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Speech Model

    private var modelStep: some View {
        StepCard(number: 2, title: "Speech Model (~400MB)") {
            HStack {
                statusIcon(for: vm.transcriptionService.isModelLoaded)
                Text("Parakeet v3")
                Spacer()

                if vm.transcriptionService.isModelLoaded {
                    Text("Ready").foregroundStyle(.green)
                } else if vm.transcriptionService.isDownloading {
                    ProgressView(value: vm.transcriptionService.downloadProgress)
                        .frame(width: 100)
                    Text("\(Int(vm.transcriptionService.downloadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                } else {
                    Button("Download") {
                        Task { try? await vm.transcriptionService.loadModel() }
                    }
                    .controlSize(.small)
                }
            }

            if !vm.transcriptionService.isModelLoaded && !vm.transcriptionService.isDownloading {
                Text("You can also download later from Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 3: Claude CLI

    private var claudeStep: some View {
        StepCard(number: 3, title: "Claude CLI (for AI notes)", optional: true) {
            HStack {
                if isCheckingClaude {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking...")
                        .foregroundStyle(.secondary)
                } else if let path = claudePath {
                    statusIcon(for: true)
                    Text("Found")
                    Spacer()
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    statusIcon(for: false)
                    Text("Not found")
                    Spacer()
                    Button("Install Guide") {
                        NSWorkspace.shared.open(URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!)
                    }
                    .controlSize(.small)
                }
            }

            if claudePath == nil && !isCheckingClaude {
                Text("Optional - app works without it, but can't generate AI notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(for done: Bool) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .green : .secondary)
    }

    private func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
    }

    private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    private func checkClaude() {
        isCheckingClaude = true
        DispatchQueue.global().async {
            let path = NoteGenerationService.findClaudeCLI()
            let found = path != "claude" && FileManager.default.isExecutableFile(atPath: path)
            DispatchQueue.main.async {
                claudePath = found ? path : nil
                isCheckingClaude = false
            }
        }
    }
}

// MARK: - StepCard

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    var optional: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(number).")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                if optional {
                    Text("optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
