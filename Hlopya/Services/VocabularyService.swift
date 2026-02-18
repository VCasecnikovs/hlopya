import Foundation
import FluidAudio

/// Manages custom vocabulary for CTC-based transcription rescoring.
/// Scans folders for names (from filenames) and maintains a vocabulary term list.
@MainActor
@Observable
final class VocabularyService {
    private(set) var terms: [CustomVocabularyTerm] = []
    private(set) var isLoading = false
    private(set) var loadedFromPath: String?

    /// Load vocabulary terms from a folder.
    /// Extracts names from filenames like "FirstName LastName (Company).md" or "Company Name.md"
    func loadFromFolder(url: URL) async throws {
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw VocabularyError.folderNotFound(url.path)
        }

        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let mdFiles = contents.filter { $0.pathExtension == "md" }

        var newTerms: [CustomVocabularyTerm] = []
        var seen = Set<String>()

        for file in mdFiles {
            let filename = file.deletingPathExtension().lastPathComponent

            // Skip templates, MOCs, index files
            if filename.hasPrefix("_") || filename.hasPrefix(".") { continue }

            // Extract name: "FirstName LastName (Company).md" -> "FirstName LastName"
            let name: String
            if let parenStart = filename.firstIndex(of: "(") {
                name = String(filename[..<parenStart]).trimmingCharacters(in: .whitespaces)
            } else {
                name = filename.trimmingCharacters(in: .whitespaces)
            }

            guard name.count >= 2, !seen.contains(name.lowercased()) else { continue }
            seen.insert(name.lowercased())

            // Add the full name, with word aliases for multi-word names
            let words = name.split(separator: " ").map(String.init)
            let aliases = words.count > 1 ? words.filter { $0.count >= 3 } : nil
            newTerms.append(CustomVocabularyTerm(
                text: name,
                weight: 10.0,
                aliases: aliases?.isEmpty == true ? nil : aliases
            ))

            // Extract company from parentheses if present
            if let parenStart = filename.firstIndex(of: "("),
               let parenEnd = filename.firstIndex(of: ")") {
                let company = String(filename[filename.index(after: parenStart)..<parenEnd])
                    .trimmingCharacters(in: .whitespaces)
                if company.count >= 2, !seen.contains(company.lowercased()) {
                    seen.insert(company.lowercased())
                    newTerms.append(CustomVocabularyTerm(text: company, weight: 8.0))
                }
            }
        }

        terms = newTerms
        loadedFromPath = url.path
        print("[VocabularyService] Loaded \(terms.count) terms from \(url.lastPathComponent)")
    }

    /// Add a single term manually
    func addTerm(_ text: String) {
        guard !text.isEmpty else { return }
        let exists = terms.contains { $0.text.lowercased() == text.lowercased() }
        guard !exists else { return }
        terms.append(CustomVocabularyTerm(text: text, weight: 10.0))
    }

    /// Remove a term by text
    func removeTerm(_ text: String) {
        terms.removeAll { $0.text == text }
    }

    /// Clear all terms
    func clearAll() {
        terms = []
        loadedFromPath = nil
    }

    /// Build a CustomVocabularyContext from current terms (for FluidAudio)
    func buildContext() -> CustomVocabularyContext? {
        guard !terms.isEmpty else { return nil }
        return CustomVocabularyContext(terms: terms)
    }
}

enum VocabularyError: LocalizedError {
    case folderNotFound(String)
    case ctcModelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let path): return "Folder not found: \(path)"
        case .ctcModelLoadFailed(let msg): return "CTC model load failed: \(msg)"
        }
    }
}
