import SwiftUI

struct WatchRecorderView: View {
    private static let defaultServerURL = "http://100.82.35.56:18788/api/hlopya/watch/upload"

    @State private var recorder = WatchRecorder()
    @State private var uploader = KlavaUploader()
    @AppStorage("serverURL") private var serverURL = Self.defaultServerURL
    @AppStorage("webhookToken") private var webhookToken = ""
    @AppStorage("recordingTitle") private var recordingTitle = "Watch Recording"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusHeader

                    if recorder.isRecording {
                        activeCaptureControls
                    } else {
                        readyCaptureControls
                    }

                    secondaryControls

                    if let statusText {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(statusColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }
            .navigationTitle("Hlopya")
            .onAppear {
                if serverURL.contains("YOUR-MAC")
                    || serverURL.contains("192.168.1.207")
                    || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    serverURL = Self.defaultServerURL
                }
                uploader.refreshPendingCount()
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "figure.walk.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(recorder.isRecording ? .orange : .green)

            Text(recorder.isRecording ? "Capturing" : "Ready")
                .font(.headline)

            Text(recorder.isRecording ? recorder.formattedElapsed : readinessText)
                .font(.system(size: recorder.isRecording ? 28 : 14, weight: .semibold, design: recorder.isRecording ? .monospaced : .default))
                .contentTransition(.numericText())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var readyCaptureControls: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await startCapture()
                }
            } label: {
                Label("Start Capture", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            TextField("Title", text: $recordingTitle)
                .textInputAutocapitalization(.words)
        }
    }

    private var activeCaptureControls: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await finishCapture()
                }
            } label: {
                Label("Finish", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Text("Saved locally first. Upload starts after finish.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var secondaryControls: some View {
        VStack(spacing: 8) {
            if !recorder.isRecording {
                Button {
                    Task {
                        await syncPending()
                    }
                } label: {
                    Label(
                        uploader.isUploading ? "Sending" : retryTitle,
                        systemImage: uploader.isUploading ? "arrow.triangle.2.circlepath" : "tray.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .disabled(uploader.isUploading || uploader.pendingCount == 0)
            }

            NavigationLink {
                ServerSettingsView(serverURL: $serverURL, webhookToken: $webhookToken)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.footnote)
    }

    private var readinessText: String {
        if uploader.pendingCount > 0 {
            return "\(uploader.pendingCount) waiting to send"
        }
        return "Start a meeting, walk, or thought"
    }

    private var retryTitle: String {
        uploader.pendingCount == 1 ? "Send 1 Capture" : "Send \(uploader.pendingCount)"
    }

    private var statusText: String? {
        if let error = recorder.errorMessage ?? uploader.errorMessage {
            return error
        }
        if uploader.lastResponse != nil {
            return "Sent to Hlopya"
        }
        return nil
    }

    private var statusColor: Color {
        if recorder.errorMessage != nil || uploader.errorMessage != nil {
            return .orange
        }
        return .green
    }

    private func startCapture() async {
        await recorder.start()
        uploader.refreshPendingCount()
    }

    private func finishCapture() async {
        recorder.stop()
        uploader.refreshPendingCount()
        await syncPending()
    }

    private func syncPending() async {
        await uploader.syncPending(
            serverURL: serverURL,
            token: webhookToken,
            title: recordingTitle
        )
    }
}

private struct ServerSettingsView: View {
    @Binding var serverURL: String
    @Binding var webhookToken: String

    var body: some View {
        Form {
            TextField("Upload URL", text: $serverURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Token", text: $webhookToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .navigationTitle("Server")
    }
}
