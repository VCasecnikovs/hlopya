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
                        .font(HlopTypography.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showCopied ? HlopColors.statusDone : .secondary)
                .accessibilityLabel("Copy notes")

                Button {
                    editText = markdown
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(HlopTypography.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Edit notes")
            }
            .padding(.bottom, HlopSpacing.md)

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
                .font(HlopTypography.callout)
                .frame(minHeight: 300)
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(HlopColors.primary.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: HlopSpacing.sm) {
                Button("Save") {
                    onSave(editText)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Save changes")

                Button("Cancel") {
                    isEditing = false
                }
                .controlSize(.small)
                .accessibilityLabel("Cancel editing")
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
                .font(HlopTypography.title3)
                .padding(.top, HlopSpacing.lg)
                .padding(.bottom, HlopSpacing.xs)

        case .userNote:
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(HlopColors.primary)
                    .frame(width: 3)
                Text(block.text)
                    .font(HlopTypography.callout).fontWeight(.semibold)
                    .padding(.leading, HlopSpacing.md)
            }
            .padding(.vertical, 3)

        case .aiContext:
            Text(block.text)
                .font(HlopTypography.callout)
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
