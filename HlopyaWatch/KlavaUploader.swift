import Foundation
import Observation

@MainActor
@Observable
final class KlavaUploader {
    private(set) var isUploading = false
    private(set) var lastResponse: String?
    var errorMessage: String?

    func upload(
        fileURL: URL,
        serverURL: String,
        token: String,
        title: String,
        recordedAt: Date?
    ) async {
        guard let endpoint = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Bad server URL"
            return
        }

        isUploading = true
        errorMessage = nil
        lastResponse = nil
        defer { isUploading = false }

        do {
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
                    "recorded_at": ISO8601DateFormatter().string(from: recordedAt ?? Date()),
                ]
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: data, encoding: .utf8) ?? ""

            guard (200..<300).contains(status) else {
                errorMessage = "Upload failed \(status): \(text)"
                return
            }

            lastResponse = text.isEmpty ? "Uploaded" : text
        } catch {
            errorMessage = error.localizedDescription
        }
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

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
