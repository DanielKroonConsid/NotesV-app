import Foundation

/// Turns note titles and folder names into safe file and directory names.
enum FileNaming {
    static let noteExtension = "md"
    static let untitled = "Untitled"
    private static let maximumLength = 80
    private static let forbiddenCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        .union(.controlCharacters)
        .union(.newlines)

    /// A file-system safe version of `name`, or "Untitled" if nothing is left.
    static func sanitizedName(_ name: String) -> String {
        let cleaned = name.unicodeScalars
            .map { forbiddenCharacters.contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        var result = String(cleaned.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
        while result.hasPrefix(".") {
            result.removeFirst()
        }
        result = result.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? untitled : result
    }

    /// The file name for a note with the given title, e.g. "Weekly sync.md" or "Weekly sync (2).md".
    static func noteFileName(title: String, number: Int = 1) -> String {
        let base = sanitizedName(title)
        let suffix = number > 1 ? " (\(number))" : ""
        return "\(base)\(suffix).\(noteExtension)"
    }

    /// The title part of a note file name, without the extension or a " (n)" suffix.
    static func baseName(ofNoteFileName fileName: String) -> String {
        var name = (fileName as NSString).deletingPathExtension
        if let range = name.range(of: #" \(\d+\)$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }
}
