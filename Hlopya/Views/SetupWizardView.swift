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
            VStack(spacing: HlopSpacing.sm) {
                Image(systemName: "mic.badge.xmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Welcome to Hlopya")
                    .font(HlopTypography.title)
                Text("Meeting recorder & note-taker")
                    .font(HlopTypography.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .padding(.bottom, HlopSpacing.xxl)

            // Steps
            VStack(spacing: HlopSpacing.lg) {
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
            .accessibilityLabel("Get started with Hlopya")

            if !canProceed {
                Text("Grant microphone permission to continue")
                    .font(HlopTypography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, HlopSpacing.lg)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Text("Granted").foregroundStyle(HlopColors.statusDone)
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
                    .accessibilityLabel("Grant microphone permission")
                }
            }

            // System Audio
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(HlopColors.primary)
                Text("System Audio")
                Spacer()
                Text("Prompted on first record")
                    .font(HlopTypography.caption)
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
                    Text("Ready").foregroundStyle(HlopColors.statusDone)
                } else if vm.transcriptionService.isDownloading {
                    ProgressView(value: vm.transcriptionService.downloadProgress)
                        .frame(width: 100)
                    Text("\(Int(vm.transcriptionService.downloadProgress * 100))%")
                        .font(HlopTypography.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                } else {
                    Button("Download") {
                        Task { try? await vm.transcriptionService.loadModel() }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Download speech model")
                }
            }

            if !vm.transcriptionService.isModelLoaded && !vm.transcriptionService.isDownloading {
                Text("You can also download later from Settings.")
                    .font(HlopTypography.caption)
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
                        .font(HlopTypography.caption)
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
                    .font(HlopTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(for done: Bool) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? HlopColors.statusDone : .secondary)
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
        VStack(alignment: .leading, spacing: HlopSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(number).")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                if optional {
                    Text("optional")
                        .font(HlopTypography.caption)
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
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}
