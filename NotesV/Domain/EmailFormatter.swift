import Foundation

/// Turns a note into text for an email: HTML for mail apps, and plain text as a fallback.
///
/// List markers and checkboxes are drawn by the editor and aren't part of the note's text,
/// so they are added here. Inline styles keep the look when a mail app strips style sheets.
enum EmailFormatter {
    // MARK: - HTML

    static func html(for document: NoteDocument) -> String {
        var body = ""
        var index = 0
        let blocks = document.blocks

        while index < blocks.count {
            switch blocks[index] {
            case .paragraph(.monostyled, _):
                var lines: [String] = []
                while index < blocks.count, case .paragraph(.monostyled, let text) = blocks[index] {
                    lines.append(escaped(text.plainText))
                    index += 1
                }
                body += #"<pre style="font-family:Menlo,Consolas,monospace;font-size:13px;margin:0 0 12px">"#
                    + lines.joined(separator: "\n") + "</pre>"

            case .paragraph(let style, let text):
                index += 1
                guard !text.isEmpty else { continue }
                body += paragraphHTML(style, text)

            case .listItem:
                var items: [ListItem] = []
                while index < blocks.count, case .listItem(let item) = blocks[index] {
                    items.append(item)
                    index += 1
                }
                body += listHTML(items)

            case .table(let table):
                index += 1
                body += tableHTML(table)
            }
        }

        return """
        <html><head><meta charset="utf-8"></head><body>\
        <div style="font-family:-apple-system,Segoe UI,Arial,sans-serif;font-size:14px;line-height:1.4">\
        \(body)</div></body></html>
        """
    }

    private static func paragraphHTML(_ style: ParagraphStyle, _ text: RichText) -> String {
        let content = inlineHTML(text)
        return switch style {
        case .title: #"<h1 style="font-size:24px;margin:0 0 12px">\#(content)</h1>"#
        case .heading: #"<h2 style="font-size:18px;margin:18px 0 8px">\#(content)</h2>"#
        case .subheading: #"<h3 style="font-size:15px;margin:14px 0 6px">\#(content)</h3>"#
        case .body, .monostyled: #"<p style="margin:0 0 10px">\#(content)</p>"#
        }
    }

    /// Nested lists go inside the `<li>` of their parent, so an `<li>` stays open until the next
    /// item at the same or a lower level.
    private static func listHTML(_ items: [ListItem]) -> String {
        var html = ""
        var openLists: [String] = []

        func open(_ listTag: String) {
            let style = listTag == "ol" || listTag == "ul" ? "" : #" style="list-style:none;padding-left:0""#
            html += "<\(listTag == "ol" ? "ol" : "ul")\(style)>"
            openLists.append(listTag)
        }
        func closeLast() {
            let listTag = openLists.removeLast()
            html += "</li></\(listTag == "ol" ? "ol" : "ul")>"
        }

        for item in items {
            let depth = item.level + 1
            let listTag = switch item.kind {
            case .bulleted: "ul"
            case .numbered: "ol"
            case .dashed, .checklist: "marked" // These show their own marker in the text.
            }

            while openLists.count > depth { closeLast() }
            if openLists.count == depth, openLists.last != listTag { closeLast() }
            if openLists.count == depth { html += "</li>" }
            while openLists.count < depth {
                open(listTag)
                if openLists.count < depth { html += #"<li style="list-style:none">"# }
            }
            html += "<li>" + (marker(for: item).map { "\($0) " } ?? "") + inlineHTML(item.text)
        }
        while !openLists.isEmpty { closeLast() }
        return html
    }

    private static func tableHTML(_ table: NoteTable) -> String {
        let rows = table.rows.map { row in
            let cells = row.map { #"<td style="border:1px solid #bbb;padding:6px 8px">\#(inlineHTML($0))</td>"# }
            return "<tr>" + cells.joined() + "</tr>"
        }
        return #"<table style="border-collapse:collapse;margin:0 0 12px">"# + rows.joined() + "</table>"
    }

    private static func inlineHTML(_ text: RichText) -> String {
        text.runs.map { run in
            var html = escaped(run.text)
            if run.style.contains(.bold) { html = "<b>\(html)</b>" }
            if run.style.contains(.italic) { html = "<i>\(html)</i>" }
            if run.style.contains(.underline) { html = "<u>\(html)</u>" }
            if run.style.contains(.strikethrough) { html = "<s>\(html)</s>" }
            return html
        }.joined()
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Plain text

    static func plainText(for document: NoteDocument) -> String {
        var lines: [String] = []
        var counters: [Int] = []

        for block in document.blocks {
            if case .listItem(let item) = block {
                counters = Array(counters.prefix(item.level + 1))
                counters += Array(repeating: 0, count: item.level + 1 - counters.count)
                var listMarker = marker(for: item) ?? "•"
                if item.kind == .numbered {
                    counters[item.level] += 1
                    listMarker = "\(counters[item.level])."
                }
                let indent = String(repeating: " ", count: item.level * 4)
                lines.append("\(indent)\(listMarker) \(item.text.plainText)")
                continue
            }
            counters = []

            switch block {
            case .paragraph(.title, let text), .paragraph(.heading, let text), .paragraph(.subheading, let text):
                if !lines.isEmpty, lines.last != "" { lines.append("") }
                lines.append(text.plainText)
            case .paragraph(_, let text):
                lines.append(text.plainText)
            case .table(let table):
                lines += table.rows.map { $0.map(\.plainText).joined(separator: "\t") }
            case .listItem:
                break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The marker written in the text, for list kinds a mail app has no list style for.
    private static func marker(for item: ListItem) -> String? {
        switch item.kind {
        case .bulleted, .numbered: nil
        case .dashed: "–"
        case .checklist: item.isChecked ? "☑" : "☐"
        }
    }
}
