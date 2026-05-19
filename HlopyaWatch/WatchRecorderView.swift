import SwiftUI

struct WatchRecorderView: View {
    private static let defaultServerURL = "http://192.168.1.207:18788/api/hlopya/watch/upload"

    @State private var recorder = WatchRecorder()
    @State private var uploader = KlavaUploader()
    @AppStorage("serverURL") private var serverURL = Self.defaultServerURL
    @AppStorage("webhookToken") private var webhookToken = ""
    @AppStorage("recordingTitle") private var recordingTitle = "Watch Recording"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text(recorder.formattedElapsed)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())

                    Button {
                        Task {
                            await recorder.toggle()
                            uploader.refreshPendingCount()
                        }
                    } label: {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                            .font(.system(size: 38))
                            .frame(width: 78, height: 78)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recorder.isRecording ? .red : .blue)

                    if !recorder.isRecording {
                        Button {
                            Task {
                                await uploader.syncPending(
                                    serverURL: serverURL,
                                    token: webhookToken,
                                    title: recordingTitle
                                )
                            }
                        } label: {
                            Label(
                                uploader.isUploading ? "Syncing" : "Sync \(uploader.pendingCount)",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(uploader.isUploading || uploader.pendingCount == 0)
                    }

                    TextField("Title", text: $recordingTitle)
                        .textInputAutocapitalization(.words)

                    NavigationLink("Server") {
                        ServerSettingsView(serverURL: $serverURL, webhookToken: $webhookToken)
                    }

                    if let error = recorder.errorMessage ?? uploader.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if uploader.lastResponse != nil {
                        Label("Uploaded", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Hlopya")
            .onAppear {
                if serverURL.contains("YOUR-MAC") || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    serverURL = Self.defaultServerURL
                }
                uploader.refreshPendingCount()
            }
        }
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
