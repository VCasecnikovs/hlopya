import Foundation
import Observation

@MainActor
@Observable
final class KlavaUploader {
    private let syncedRecordingsKey = "syncedRecordingFiles"

    private(set) var isUploading = false
    private(set) var lastResponse: String?
    private(set) var pendingCount = 0
    var errorMessage: String?

    init() {
        refreshPendingCount()
    }

    func upload(
        fileURL: URL,
        serverURL: String,
        token: String,
        title: String,
        recordedAt: Date?
    ) async -> Bool {
        guard let endpoint = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Bad server URL"
            return false
        }

        isUploading = true
        errorMessage = nil
        lastResponse = nil
        defer { isUploading = false }

        do {
            let text = try await performUpload(
                endpoint: endpoint,
                fileURL: fileURL,
                token: token,
                title: title,
                recordedAt: recordedAt ?? Date()
            )
            markSynced(fileURL)
            lastResponse = text.isEmpty ? "Uploaded" : text
            refreshPendingCount()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func syncPending(serverURL: String, token: String, title: String) async {
        guard let endpoint = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Bad server URL"
            return
        }

        isUploading = true
        errorMessage = nil
        lastResponse = nil
        defer {
            isUploading = false
            refreshPendingCount()
        }

        let pending = pendingRecordings()
        guard !pending.isEmpty else {
            lastResponse = "Nothing to sync"
            return
        }

        var uploaded = 0
        for recording in pending {
            do {
                _ = try await performUpload(
                    endpoint: endpoint,
                    fileURL: recording.url,
                    token: token,
                    title: title.isEmpty ? recording.url.deletingPathExtension().lastPathComponent : title,
                    recordedAt: recording.createdAt
                )
                markSynced(recording.url)
                uploaded += 1
            } catch {
                errorMessage = "Synced \(uploaded)/\(pending.count). \(error.localizedDescription)"
                return
            }
        }

        lastResponse = "Synced \(uploaded)"
    }

    func refreshPendingCount() {
        pendingCount = pendingRecordings().count
    }

    private func pendingRecordings() -> [WatchRecording] {
        let synced = Set(UserDefaults.standard.stringArray(forKey: syncedRecordingsKey) ?? [])
        return WatchRecorder.recordings().filter { !synced.contains($0.id) }
    }

    private func markSynced(_ fileURL: URL) {
        var synced = Set(UserDefaults.standard.stringArray(forKey: syncedRecordingsKey) ?? [])
        synced.insert(fileURL.lastPathComponent)
        UserDefaults.standard.set(Array(synced), forKey: syncedRecordingsKey)
    }

    private func performUpload(
        endpoint: URL,
        fileURL: URL,
        token: String,
        title: String,
        recordedAt: Date
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = "HlopyaBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.multipartBody(
            boundary: boundary,
            fileURL: fileURL,
            fields: [
                "title": title.isEmpty ? "Watch Recording" : title,
                "source": "apple-watch",
                "recorded_at": ISO8601DateFormatter().string(from: recordedAt),
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(status) else {
            throw UploadError.http(status: status, body: text)
        }

        return text
    }

    private static func multipartBody(
        boundary: String,
        fileURL: URL,
        fields: [String: String]
    ) throws -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        for (name, value) in fields {
            body.append("--\(boundary)\(lineBreak)")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            body.append("\(value)\(lineBreak)")
        }

        let fileData = try Data(contentsOf: fileURL)
        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\(lineBreak)")
        body.append("Content-Type: audio/mp4\(lineBreak)\(lineBreak)")
        body.append(fileData)
        body.append(lineBreak)
        body.append("--\(boundary)--\(lineBreak)")
        return body
    }
}

private enum UploadError: LocalizedError {
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case let .http(status, body):
            return "Upload failed \(status): \(body)"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
