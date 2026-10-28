import Foundation

/// Inline formatting that can be combined on a run of text.
struct InlineStyle: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let underline = InlineStyle(rawValue: 1 << 2)
    static let strikethrough = InlineStyle(rawValue: 1 << 3)

    /// Styles that are invisible on whitespace.
    static let emphasis: InlineStyle = [.bold, .italic]
}

/// A piece of text that shares one inline style.
struct TextRun: Hashable, Sendable {
    var text: String
    var style: InlineStyle

    init(_ text: String, style: InlineStyle = []) {
        self.text = text
        self.style = style
    }
}

/// One line of text with inline formatting.
///
/// The runs are always kept in a canonical form, so two values that look the same compare equal:
/// adjacent runs with the same style are merged, empty runs are dropped, and bold/italic only cover
/// whitespace that sits *inside* a bold/italic region. That last rule lets Markdown emphasis markers
/// always sit next to non-whitespace characters, which Markdown requires.
struct RichText: Hashable, Sendable, ExpressibleByStringLiteral {
    private(set) var runs: [TextRun]

    init(_ runs: [TextRun] = []) {
        self.runs = Self.canonicalize(runs)
    }

    init(plain text: String) {
        self.init([TextRun(text)])
    }

    init(stringLiteral value: String) {
        self.init(plain: value)
    }

    var plainText: String { runs.map(\.text).joined() }

    var isEmpty: Bool { runs.isEmpty }

    static func + (lhs: RichText, rhs: RichText) -> RichText {
        RichText(lhs.runs + rhs.runs)
    }

    private static func canonicalize(_ runs: [TextRun]) -> [TextRun] {
        var characters: [(Character, InlineStyle)] = []
        for run in runs {
            for character in run.text {
                characters.append((character, run.style))
            }
        }

        // Drop bold/italic from whitespace unless the nearest non-whitespace
        // characters on both sides carry the same style.
        let styles = characters.map(\.1)
        let isWhitespace = characters.map { $0.0.isWhitespace }
        var previousSolid: Int?
        var previousSolidIndex = [Int?](repeating: nil, count: characters.count)
        for index in characters.indices {
            previousSolidIndex[index] = previousSolid
            if !isWhitespace[index] { previousSolid = index }
        }
        var nextSolid: Int?
        for index in characters.indices.reversed() {
            if isWhitespace[index] {
                var allowed: InlineStyle = []
                if let previous = previousSolidIndex[index], let next = nextSolid {
                    allowed = styles[previous].intersection(styles[next]).intersection(.emphasis)
                }
                let removed = styles[index].intersection(.emphasis).subtracting(allowed)
                characters[index].1.subtract(removed)
            } else {
                nextSolid = index
            }
        }

        var result: [TextRun] = []
        for (character, style) in characters {
            if let last = result.last, last.style == style {
                result[result.count - 1].text.append(character)
            } else {
                result.append(TextRun(String(character), style: style))
            }
        }
        return result
    }
}
