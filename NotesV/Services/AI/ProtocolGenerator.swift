import Foundation

struct ProtocolGenerationResult: Sendable {
    var minutes: MeetingProtocol
    /// The model that wrote the protocol, if the provider reports one.
    var modelID: String?
    /// Shown to the user, e.g. when an older cached model had to be used.
    var warning: String?
}

/// Writes a meeting protocol from meeting details and the user's notes.
///
/// The rest of the app only depends on this protocol, never on a concrete provider.
protocol ProtocolGenerator: Sendable {
    func generateProtocol(
        meeting: MeetingDetails,
        notes: NoteDocument,
        language: ProtocolLanguage
    ) async throws -> ProtocolGenerationResult
}
