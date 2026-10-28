import AppKit

/// The kind of paragraph, stored on every character of the paragraph in the text view.
enum ParagraphKind: Hashable {
    case style(ParagraphStyle)
    case list(ListKind)

    init(attributeValue: Any?) {
        guard let raw = attributeValue as? String else {
            self = .style(.body)
            return
        }
        if raw.hasPrefix("list."), let kind = ListKind(rawValue: String(raw.dropFirst(5))) {
            self = .list(kind)
        } else {
            self = .style(ParagraphStyle(rawValue: raw) ?? .body)
        }
    }

    var attributeValue: String {
        switch self {
        case .style(let style): style.rawValue
        case .list(let kind): "list." + kind.rawValue
        }
    }

    var listKind: ListKind? {
        if case .list(let kind) = self { kind } else { nil }
    }
}

extension NSAttributedString.Key {
    /// `String`: the `ParagraphKind` of the paragraph.
    static let notesParagraphKind = NSAttributedString.Key("NotesV.paragraphKind")
    /// `Int`: the indent level of a list item.
    static let notesListLevel = NSAttributedString.Key("NotesV.listLevel")
    /// `Bool`: whether a checklist item is checked.
    static let notesChecked = NSAttributedString.Key("NotesV.checked")
    /// `Bool`: inline bold. Stored separately from the font, because headings are always bold.
    static let notesBold = NSAttributedString.Key("NotesV.bold")
    /// `Bool`: inline italic.
    static let notesItalic = NSAttributedString.Key("NotesV.italic")
}

/// The paragraph-level attributes of one paragraph.
struct ParagraphAttributes: Equatable {
    var kind: ParagraphKind = .style(.body)
    var level = 0
    var isChecked = false

    init(kind: ParagraphKind = .style(.body), level: Int = 0, isChecked: Bool = false) {
        self.kind = kind
        self.level = kind.listKind == nil ? 0 : min(max(level, 0), ListItem.maximumLevel)
        self.isChecked = kind == .list(.checklist) && isChecked
    }

    init(_ attributes: [NSAttributedString.Key: Any]) {
        self.init(
            kind: ParagraphKind(attributeValue: attributes[.notesParagraphKind]),
            level: attributes[.notesListLevel] as? Int ?? 0,
            isChecked: attributes[.notesChecked] as? Bool ?? false
        )
    }
}

/// Fonts, colors and spacing that mimic Apple Notes.
@MainActor
enum NotesTextStyle {
    static let listIndentPerLevel: CGFloat = 22
    static let listMarkerWidth: CGFloat = 22
    static let checklistMarkerWidth: CGFloat = 26
    static let monostyledInset: CGFloat = 8

    static func baseFont(for kind: ParagraphKind) -> NSFont {
        switch kind {
        case .style(.title): .systemFont(ofSize: 24, weight: .bold)
        case .style(.heading): .systemFont(ofSize: 18, weight: .bold)
        case .style(.subheading): .systemFont(ofSize: 15, weight: .semibold)
        case .style(.monostyled): .monospacedSystemFont(ofSize: 12, weight: .regular)
        case .style(.body), .list: .systemFont(ofSize: 13)
        }
    }

    static func font(for kind: ParagraphKind, inline: InlineStyle) -> NSFont {
        let base = baseFont(for: kind)
        var traits = base.fontDescriptor.symbolicTraits
        if inline.contains(.bold) { traits.insert(.bold) }
        if inline.contains(.italic) { traits.insert(.italic) }
        guard traits != base.fontDescriptor.symbolicTraits else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize) ?? base
    }

    static func paragraphStyle(for paragraph: ParagraphAttributes, textBlocks: [NSTextBlock] = []) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.textBlocks = textBlocks
        style.lineHeightMultiple = 1.08
        switch paragraph.kind {
        case .style(.title):
            style.paragraphSpacing = 6
        case .style(.heading):
            style.paragraphSpacingBefore = 4
            style.paragraphSpacing = 4
        case .style(.subheading):
            style.paragraphSpacingBefore = 2
            style.paragraphSpacing = 2
        case .style(.monostyled):
            style.headIndent = monostyledInset
            style.firstLineHeadIndent = monostyledInset
            style.tailIndent = -monostyledInset
        case .style(.body):
            style.paragraphSpacing = 2
        case .list(let kind):
            let markerWidth = kind == .checklist ? checklistMarkerWidth : listMarkerWidth
            let indent = CGFloat(paragraph.level) * listIndentPerLevel + markerWidth
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            style.paragraphSpacing = kind == .checklist ? 4 : 2
        }
        return style
    }

    /// All attributes for a character with the given paragraph and inline style.
    static func attributes(
        paragraph: ParagraphAttributes,
        inline: InlineStyle,
        textBlocks: [NSTextBlock] = []
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: paragraph.kind, inline: inline),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle(for: paragraph, textBlocks: textBlocks),
            .notesParagraphKind: paragraph.kind.attributeValue,
        ]
        if paragraph.kind.listKind != nil {
            attributes[.notesListLevel] = paragraph.level
        }
        if paragraph.isChecked {
            attributes[.notesChecked] = true
        }
        if inline.contains(.bold) {
            attributes[.notesBold] = true
        }
        if inline.contains(.italic) {
            attributes[.notesItalic] = true
        }
        if inline.contains(.underline) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if inline.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    static func inlineStyle(from attributes: [NSAttributedString.Key: Any]) -> InlineStyle {
        var style: InlineStyle = []
        if attributes[.notesBold] as? Bool == true { style.insert(.bold) }
        if attributes[.notesItalic] as? Bool == true { style.insert(.italic) }
        if (attributes[.underlineStyle] as? Int ?? 0) != 0 { style.insert(.underline) }
        if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { style.insert(.strikethrough) }
        return style
    }

    static var accentColor: NSColor {
        NSColor(named: "AccentColor") ?? .systemYellow
    }
}
