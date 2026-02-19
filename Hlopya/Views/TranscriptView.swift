import SwiftUI

/// Displays transcript with speaker-colored segments.
/// Me = green, Them = cyan. Clean layout with copy button.
struct TranscriptView: View {
    let markdown: String
    let participantNames: [String: String]
    var segments: [TranscriptSegment] = []
    @State private var showCopied = false
    @State private var lines: [TranscriptLine] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Speaker color legend + copy button
            HStack(spacing: HlopSpacing.lg) {
                HStack(spacing: HlopSpacing.xs) {
                    Circle().fill(HlopColors.statusMe).frame(width: 6, height: 6)
                    Text("Me").font(HlopTypography.footnote).foregroundStyle(.secondary)
                }
                HStack(spacing: HlopSpacing.xs) {
                    Circle().fill(HlopColors.statusThem).frame(width: 6, height: 6)
                    Text("Them").font(HlopTypography.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    let plain = lines.map { line in
                        let speaker = line.displaySpeaker ?? ""
                        let ts = line.timestamp ?? ""
                        return "\(speaker) \(ts): \(line.text)"
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(plain, forType: .string)
                    withAnimation { showCopied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Label(showCopied ? "Copied" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(HlopTypography.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showCopied ? HlopColors.statusDone : .secondary)
                .accessibilityLabel("Copy transcript")
            }
            .padding(.bottom, HlopSpacing.md)

            // Transcript lines - LazyVStack for performance
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    TranscriptLineView(line: line)
                }
            }
        }
        .textSelection(.enabled)
        .onAppear { lines = parseLines() }
        .onChange(of: markdown) { _, _ in lines = parseLines() }
        .onChange(of: segments.count) { _, _ in lines = parseLines() }
    }

    private func parseLines() -> [TranscriptLine] {
        var segmentIndex = 0
        return markdown
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> TranscriptLine? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                // Skip markdown headers and metadata
                if trimmed.hasPrefix("#") || trimmed.hasPrefix("- ") || trimmed == "---" {
                    return nil
                }

                // Parse: **Speaker** [timestamp]: text
                if trimmed.range(of: #"\*\*(\w+)\*\*"#, options: .regularExpression) != nil {
                    var parsed = parseSegmentLine(trimmed)
                    // Match confidence from transcript segments by order
                    if segmentIndex < segments.count {
                        parsed?.confidence = segments[segmentIndex].confidence
                    }
                    segmentIndex += 1
                    return parsed
                }

                return nil
            }
    }

    private func parseSegmentLine(_ line: String) -> TranscriptLine? {
        guard let starStart = line.range(of: "**"),
              let starEnd = line[starStart.upperBound...].range(of: "**") else {
            return nil
        }

        let rawSpeaker = String(line[starStart.upperBound..<starEnd.lowerBound])
        let rest = String(line[starEnd.upperBound...]).trimmingCharacters(in: .whitespaces)

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
    var confidence: Float?
}

struct TranscriptLineView: View {
    let line: TranscriptLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let speaker = line.displaySpeaker {
                Text(speaker)
                    .font(HlopTypography.body).fontWeight(.semibold)
                    .foregroundStyle(line.isMe ? HlopColors.statusMe : HlopColors.statusThem)
                    .frame(width: 80, alignment: .trailing)
            }

            if let ts = line.timestamp {
                Text(formatTimestamp(ts))
                    .font(HlopTypography.monoCaption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, HlopSpacing.sm)
                    .frame(width: 60)
            } else {
                Spacer()
                    .frame(width: line.displaySpeaker != nil ? 68 : 0)
            }

            Text(line.text)
                .font(HlopTypography.body)
                .foregroundStyle(isLowConfidence ? HlopColors.statusWarning : .primary)
                .padding(.leading, HlopSpacing.sm)

            if let conf = line.confidence {
                Text("\(Int(conf * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(isLowConfidence ? HlopColors.statusWarning : Color.secondary.opacity(0.4))
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 3)
    }

    private var isLowConfidence: Bool {
        line.confidence.map { $0 < 0.5 } == true
    }

    /// Convert raw timestamp like "[00:45]" or "[123.4s]" to "0:45" format
    private func formatTimestamp(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        // Already in mm:ss format
        if cleaned.contains(":") {
            return cleaned
        }
        // Seconds format (e.g. "45.2s" or "123")
        let numStr = cleaned.replacingOccurrences(of: "s", with: "")
        if let seconds = Double(numStr) {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return String(format: "%d:%02d", m, s)
        }
        return cleaned
    }
}
