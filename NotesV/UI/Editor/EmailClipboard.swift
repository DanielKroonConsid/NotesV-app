import AppKit

/// Puts a note on the clipboard so that it keeps its formatting when pasted into an email.
@MainActor
enum EmailClipboard {
    struct Contents {
        var html: String
        var rtf: Data?
        var plainText: String
    }

    static func contents(for document: NoteDocument) -> Contents {
        let html = EmailFormatter.html(for: document)
        // Some mail apps prefer RTF. Without it they still have the HTML.
        let attributed = try? NSAttributedString(
            data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
        let rtf = attributed.flatMap { $0.rtf(from: NSRange(location: 0, length: $0.length)) }
        return Contents(html: html, rtf: rtf, plainText: EmailFormatter.plainText(for: document))
    }

    static func copy(_ document: NoteDocument) {
        let contents = contents(for: document)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(contents.html, forType: .html)
        pasteboard.setString(contents.plainText, forType: .string)
        if let rtf = contents.rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
    }
}
