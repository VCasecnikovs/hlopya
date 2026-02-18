import SwiftUI

/// Renders enhanced notes markdown.
/// User's bold lines get accent left border, AI context is secondary.
/// Simplified: display mode with copy + edit, no clutter.
struct NotesView: View {
    let markdown: String
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var showCopied = false

    var body: some View {
        if isEditing {
            editMode
        } else {
            displayMode
        }
    }

    // MARK: - Display Mode

    private var displayMode: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                    withAnimation { showCopied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Label(showCopied ? "Copied" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showCopied ? .green : .secondary)

                Button {
                    editText = markdown
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            // Notes content
            ForEach(parsedBlocks) { block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Edit Mode

    private var editMode: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $editText)
                .font(.system(size: 14))
                .frame(minHeight: 300)
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("Save") {
                    onSave(editText)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancel") {
                    isEditing = false
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Parsing

    private var parsedBlocks: [NoteBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [NoteBlock] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blocks.append(NoteBlock(type: .spacer, text: ""))
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
        case .spacer:
            Spacer()
                .frame(height: 8)

        case .header:
            Text(block.text)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 16)
                .padding(.bottom, 4)

        case .userNote:
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                Text(block.text)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.leading, 12)
            }
            .padding(.vertical, 3)

        case .aiContext:
            Text(block.text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.leading, 15)
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
    case spacer
    case header
    case userNote
    case aiContext
}
