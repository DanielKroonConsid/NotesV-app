import Foundation
import NaturalLanguage

/// Decides the language of a protocol's fixed texts, such as its title and headings.
///
/// The language code in a model's answer isn't reliable: it can be missing, spelled out as
/// "Swedish", or say "en" over a Swedish protocol. So the app decides, from the user's choice
/// or from the text itself.
enum ProtocolLanguageDetector {
    static func languageCode(for language: ProtocolLanguage, minutes: MeetingProtocol, notes: NoteDocument) -> String {
        switch language {
        case .swedish, .english:
            return language.rawValue
        case .automatic:
            let generated = generatedText(of: minutes)
            let text = generated.isEmpty ? notes.plainText : generated
            return isSwedish(text) ? ProtocolLanguage.swedish.rawValue : ProtocolLanguage.english.rawValue
        }
    }

    /// The fixed texts only exist in Swedish and English, so those are the only candidates.
    private static func isSwedish(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.swedish, .english]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .swedish
    }

    private static func generatedText(of minutes: MeetingProtocol) -> String {
        let agenda = minutes.agendaItems.flatMap { [$0.title, $0.summary] }
        let parts = agenda + minutes.decisions + minutes.actionItems.map(\.task)
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
