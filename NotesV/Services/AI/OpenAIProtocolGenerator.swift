import Foundation

/// Writes protocols with any OpenAI-compatible server.
struct OpenAIProtocolGenerator: ProtocolGenerator {
    /// The ways to ask for JSON, from most to least reliable.
    enum StructuredOutputMode: Int, CaseIterable, Sendable {
        case jsonSchema
        case jsonObject
        case plainText
    }

    let configuration: AIEndpointConfiguration
    let apiKey: String?
    var transport: any HTTPTransport = URLSessionTransport()
    var modelResolver: ModelResolver
    var outputSupport: StructuredOutputSupport = .shared

    func generateProtocol(
        meeting: MeetingDetails,
        notes: NoteDocument,
        language: ProtocolLanguage
    ) async throws -> ProtocolGenerationResult {
        let client = try OpenAICompatibleClient(configuration: configuration, apiKey: apiKey, transport: transport)
        let endpointID = configuration.endpointID
        let model = try await modelResolver.resolve(configuration.modelChoice, endpointID: endpointID) {
            try await client.listModels()
        }

        // Servers that don't support a JSON mode answer 400; fall back to the next mode.
        var lastError: Error = AIServiceError.invalidResponse
        for mode in await outputSupport.modes(for: endpointID) {
            let content: String
            do {
                content = try await client.chatCompletion(
                    model: model.modelID,
                    messages: Self.messages(meeting: meeting, notes: notes, language: language, mode: mode),
                    responseFormat: Self.responseFormat(for: mode)
                )
            } catch let error as AIServiceError {
                guard case .badRequest = error, mode != .plainText else { throw error }
                lastError = error
                continue
            }
            await outputSupport.remember(mode, for: endpointID)

            let warning = model.isStale
                ? String(localized: "Couldn’t check for the newest model, so NotesV used \(model.modelID) from last time.")
                : nil
            return ProtocolGenerationResult(minutes: try Self.decodeProtocol(from: content), modelID: model.modelID, warning: warning)
        }
        throw lastError
    }

    // MARK: - Prompt

    static func responseFormat(for mode: StructuredOutputMode) -> OpenAICompatibleClient.ResponseFormat {
        switch mode {
        case .jsonSchema: .jsonSchema(name: "meeting_protocol", schema: MeetingProtocol.jsonSchema)
        case .jsonObject: .jsonObject
        case .plainText: .text
        }
    }

    static func messages(
        meeting: MeetingDetails,
        notes: NoteDocument,
        language: ProtocolLanguage,
        mode: StructuredOutputMode
    ) -> [OpenAICompatibleClient.Message] {
        let languageRule = switch language {
        case .automatic: "the same language as the notes"
        case .swedish: "Swedish"
        case .english: "English"
        }

        var system = """
        You write meeting protocols (minutes) from a person's short meeting notes.
        Answer with one JSON object only.

        Rules:
        - Use only facts from the meeting details and the notes. Never invent decisions, owners, due dates, attendees or discussion.
        - Write in \(languageRule). Set "language" to the ISO 639-1 code of that language.
        - attendeesPresent: the people the notes say attended. If the notes don't say, use the invited attendees.
        - attendeesAbsent: only people the notes say were absent.
        - agendaItems: one item per topic. Follow the meeting agenda if there is one, otherwise group the notes into topics. Write each summary as 1–4 full sentences.
        - decisions: one sentence per decision that the notes record.
        - actionItems: concrete tasks from the notes. Use null for an owner or due date that the notes don't state.
        """
        if mode != .jsonSchema {
            let schema = (try? JSONEncoder().encode(MeetingProtocol.jsonSchema)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            system += "\n\nThe JSON object must match this JSON schema:\n\(schema)"
        }

        var details = ["Title: \(meeting.title)", "Start: \(meeting.start.formatted(.iso8601))"]
        if let end = meeting.end { details.append("End: \(end.formatted(.iso8601))") }
        if !meeting.location.isEmpty { details.append("Location: \(meeting.location)") }
        if !meeting.organizer.isEmpty { details.append("Organizer: \(meeting.organizer)") }
        if !meeting.attendees.isEmpty { details.append("Invited attendees: \(meeting.attendees.joined(separator: ", "))") }
        if !meeting.agenda.isEmpty { details.append("Agenda:\n\(meeting.agenda)") }

        let user = """
        Meeting details:
        \(details.joined(separator: "\n"))

        Notes (Markdown):
        \(MarkdownCodec.encodeBody(notes))
        """
        return [.system(system), .user(user)]
    }

    // MARK: - Answer

    /// Reads the protocol from the model's answer, also when the JSON is wrapped in a Markdown code
    /// block or preceded by a reasoning model's `<think>` section.
    static func decodeProtocol(from content: String) throws -> MeetingProtocol {
        var text = content
        if let thinkEnd = text.range(of: "</think>") {
            text = String(text[thinkEnd.upperBound...])
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw AIServiceError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(MeetingProtocol.self, from: Data(text[start...end].utf8))
        } catch {
            throw AIServiceError.invalidResponse
        }
    }
}

/// Remembers which structured output mode works for each server while the app runs, so later
/// requests don't repeat failed attempts.
actor StructuredOutputSupport {
    static let shared = StructuredOutputSupport()

    private var workingModes: [String: OpenAIProtocolGenerator.StructuredOutputMode] = [:]

    func modes(for endpointID: String) -> [OpenAIProtocolGenerator.StructuredOutputMode] {
        let all = OpenAIProtocolGenerator.StructuredOutputMode.allCases
        guard let working = workingModes[endpointID] else { return all }
        return all.filter { $0.rawValue >= working.rawValue }
    }

    func remember(_ mode: OpenAIProtocolGenerator.StructuredOutputMode, for endpointID: String) {
        workingModes[endpointID] = mode
    }
}
