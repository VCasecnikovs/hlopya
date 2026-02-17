import SwiftUI

/// Renders enriched notes markdown with user notes highlighted.
/// User's bold lines get accent left border, AI context is dimmer.
struct NotesView: View {
    let markdown: String
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var showSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEditing {
                editMode
            } else {
                displayMode
            }

            if showSaved {
                Text("Saved")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .transition(.opacity)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Display Mode

    private var displayMode: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parsedBlocks) { block in
                blockView(block)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            editText = markdown
            isEditing = true
        }
        .overlay(alignment: .bottomTrailing) {
            Text("Click to edit")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(8)
        }
    }

    // MARK: - Edit Mode

    private var editMode: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $editText)
                .font(.body)
                .frame(minHeight: 300)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 1)
                )

            HStack {
                Button("Done") {
                    onSave(editText)
                    isEditing = false
                    withAnimation {
                        showSaved = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { showSaved = false }
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Cancel") {
                    isEditing = false
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Parsing

    private var parsedBlocks: [NoteBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [NoteBlock] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            } else if trimmed.hasPrefix("## ") {
                blocks.append(NoteBlock(type: .header, text: String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("**") && trimmed.contains("**") {
                let text = trimmed.replacingOccurrences(of: "**", with: "")
                blocks.append(NoteBlock(type: .userNote, text: text))
            } else if trimmed.hasPrefix("- ") {
                blocks.append(NoteBlock(type: .aiContext, text: String(trimmed.dropFirst(2))))
            } else {
                blocks.append(NoteBlock(type: .aiContext, text: trimmed))
            }
        }

        return blocks
    }

    @ViewBuilder
    private func blockView(_ block: NoteBlock) -> some View {
        switch block.type {
        case .header:
            Text(block.text)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 6)

        case .userNote:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                Text(block.text)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.leading, 10)
            }
            .padding(.vertical, 4)

        case .aiContext:
            Text(block.text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.leading, 13)
                .padding(.vertical, 1)
        }
    }
}

struct NoteBlock: Identifiable {
    let id = UUID()
    let type: NoteBlockType
    let text: String
}

enum NoteBlockType {
    case header
    case userNote
    case aiContext
}
