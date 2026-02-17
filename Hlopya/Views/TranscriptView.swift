import SwiftUI

/// Displays transcript with speaker-colored segments.
/// Me = green (accent), Them = cyan
struct TranscriptView: View {
    let markdown: String
    let participantNames: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(parsedLines) { line in
                TranscriptLineView(line: line)
            }
        }
    }

    private var parsedLines: [TranscriptLine] {
        markdown
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TranscriptLine? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip markdown headers and metadata
                if trimmed.hasPrefix("#") || trimmed.hasPrefix("- ") || trimmed == "---" {
                    return nil
                }

                // Parse: **Speaker** [timestamp]: text
                if let match = trimmed.range(of: #"\*\*(\w+)\*\*\s*(\[[\d.]+s\])?\s*:?\s*(.*)"#, options: .regularExpression) {
                    let content = String(trimmed[match])
                    return parseSegmentLine(content)
                }

                // Plain text line
                return TranscriptLine(
                    id: UUID().uuidString,
                    speaker: nil, displaySpeaker: nil,
                    timestamp: nil, text: trimmed,
                    isMe: false
                )
            }
    }

    private func parseSegmentLine(_ line: String) -> TranscriptLine? {
        // Extract speaker
        guard let starStart = line.range(of: "**"),
              let starEnd = line[starStart.upperBound...].range(of: "**") else {
            return nil
        }

        let rawSpeaker = String(line[starStart.upperBound..<starEnd.lowerBound])
        let rest = String(line[starEnd.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Extract optional timestamp
        var timestamp: String?
        var text = rest
        if rest.hasPrefix("["), let closeBracket = rest.firstIndex(of: "]") {
            timestamp = String(rest[rest.startIndex...closeBracket])
            text = String(rest[rest.index(after: closeBracket)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .trimmingCharacters(in: .whitespaces)
        } else if rest.hasPrefix(":") {
            text = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let displaySpeaker = participantNames[rawSpeaker] ?? rawSpeaker
        let isMe = rawSpeaker == "Me" || rawSpeaker == "Vadim"

        return TranscriptLine(
            id: UUID().uuidString,
            speaker: rawSpeaker,
            displaySpeaker: displaySpeaker,
            timestamp: timestamp,
            text: text,
            isMe: isMe
        )
    }
}

struct TranscriptLine: Identifiable {
    let id: String
    let speaker: String?
    let displaySpeaker: String?
    let timestamp: String?
    let text: String
    let isMe: Bool
}

struct TranscriptLineView: View {
    let line: TranscriptLine

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if let speaker = line.displaySpeaker {
                Text(speaker)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(line.isMe ? .green : .cyan)
            }

            if let ts = line.timestamp {
                Text(ts)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(line.text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}
