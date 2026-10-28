import Foundation
import Testing
@testable import NotesV

struct AIEndpointConfigurationTests {
    @Test func normalizesTheBaseURL() throws {
        let configuration = AIEndpointConfiguration(preset: .custom, baseURL: "  https://example.com/v1/  ")
        #expect(try configuration.validatedBaseURL().absoluteString == "https://example.com/v1")
    }

    @Test func allowsHTTPOnlyForLocalServers() throws {
        #expect(throws: Never.self) { try AIEndpointConfiguration(preset: .ollama).validatedBaseURL() }
        #expect(throws: Never.self) {
            try AIEndpointConfiguration(preset: .custom, baseURL: "http://studio.local:1234/v1").validatedBaseURL()
        }
        #expect(throws: AIServiceError.insecureBaseURL) {
            try AIEndpointConfiguration(preset: .custom, baseURL: "http://example.com/v1").validatedBaseURL()
        }
        #expect(throws: AIServiceError.invalidBaseURL) {
            try AIEndpointConfiguration(preset: .custom, baseURL: "not a url").validatedBaseURL()
        }
        #expect(AIEndpointConfiguration(preset: .lmStudio).isLocal)
        #expect(!AIEndpointConfiguration(preset: .openAI).isLocal)
    }

    @Test func presetsChooseTheAuthHeader() {
        #expect(AIEndpointConfiguration(preset: .azureOpenAI).authStyle == .apiKey)
        #expect(AIEndpointConfiguration(preset: .openRouter).authStyle == .bearer)
    }
}

struct OpenAICompatibleClientTests {
    private func makeClient(
        _ transport: MockTransport,
        preset: AIEndpointPreset = .openAI,
        apiKey: String? = "secret"
    ) throws -> OpenAICompatibleClient {
        try OpenAICompatibleClient(configuration: AIEndpointConfiguration(preset: preset), apiKey: apiKey, transport: transport)
    }

    @Test func listsModelsWithABearerKey() async throws {
        let transport = MockTransport([.status(200, #"{"data":[{"id":"gpt-x","created":5},{"id":"local"}]}"#)])
        let models = try await makeClient(transport).listModels()

        #expect(models == [.init(id: "gpt-x", created: 5), .init(id: "local", created: nil)])
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test func usesTheAzureKeyHeader() async throws {
        let transport = MockTransport([.status(200, #"{"data":[]}"#)])
        _ = try await makeClient(transport, preset: .azureOpenAI).listModels()

        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "api-key") == "secret")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func sendsNoKeyToLocalServersWithoutOne() async throws {
        let transport = MockTransport([.status(200, #"{"data":[]}"#)])
        _ = try await makeClient(transport, preset: .ollama, apiKey: nil).listModels()

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func sendsAStrictJSONSchema() async throws {
        let transport = MockTransport([MockTransport.chatReply("{}")])
        let answer = try await makeClient(transport).chatCompletion(
            model: "gpt-x",
            messages: [.system("S"), .user("U")],
            responseFormat: .jsonSchema(name: "meeting_protocol", schema: MeetingProtocol.jsonSchema)
        )

        #expect(answer == "{}")
        let request = try #require(transport.requests.first)
        #expect(request.url?.path() == "/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        let body = transport.body(at: 0)
        #expect(body["model"] == "gpt-x")
        #expect(body["temperature"] == nil)
        #expect(body["response_format"] == [
            "type": "json_schema",
            "json_schema": ["name": "meeting_protocol", "strict": true, "schema": MeetingProtocol.jsonSchema],
        ])
    }

    @Test(arguments: [
        (401, #"{"error":{"message":"bad key"}}"#, AIServiceError.unauthorized),
        (404, "{}", .notFound),
        (429, "{}", .rateLimited),
        (400, #"{"error":"format not supported"}"#, .badRequest("format not supported")),
        (500, #"{"message":"boom"}"#, .server(status: 500, message: "boom")),
    ])
    func mapsHTTPErrors(_ status: Int, _ body: String, _ expected: AIServiceError) async throws {
        let client = try makeClient(MockTransport([.status(status, body)]))
        await #expect(throws: expected) { try await client.listModels() }
    }

    @Test func mapsConnectionErrors() async throws {
        let client = try makeClient(MockTransport([.failure(URLError(.cannotConnectToHost))]), preset: .ollama, apiKey: nil)
        await #expect(throws: AIServiceError.unreachable) { try await client.listModels() }
    }
}

struct ModelResolverTests {
    private typealias Model = OpenAICompatibleClient.Model

    private func makeResolver(now: Date = Date(timeIntervalSince1970: 1_000_000)) -> ModelResolver {
        ModelResolver(defaultsSuiteName: "NotesVTests-\(UUID().uuidString)", now: { now })
    }

    @Test func picksTheNewestTextModel() throws {
        let models = [
            Model(id: "gpt-old", created: 1), Model(id: "gpt-new", created: 3),
            Model(id: "text-embedding-3-large", created: 9), Model(id: "whisper-1", created: 9),
            Model(id: "gpt-image-1", created: 9),
        ]
        #expect(try ModelResolver.latestTextModel(in: models) == "gpt-new")
    }

    @Test func handlesServersWithoutDates() throws {
        #expect(try ModelResolver.latestTextModel(in: [Model(id: "llama3")]) == "llama3")
        #expect(throws: AIServiceError.modelSelectionRequired) {
            try ModelResolver.latestTextModel(in: [Model(id: "llama3"), Model(id: "qwen")])
        }
    }

    @Test func specificModelSkipsTheLookup() async throws {
        let resolution = try await makeResolver().resolve(.specific("my-model"), endpointID: "e") {
            Issue.record("Should not list models")
            return []
        }
        #expect(resolution == .init(modelID: "my-model", isStale: false))
    }

    @Test func cachesTheLatestModelForADay() async throws {
        let suite = "NotesVTests-\(UUID().uuidString)"
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = ModelResolver(defaultsSuiteName: suite, now: { start })
        _ = try await first.resolve(.latest, endpointID: "e") { [Model(id: "a", created: 1)] }

        let later = ModelResolver(defaultsSuiteName: suite, now: { start.addingTimeInterval(3600) })
        let cached = try await later.resolve(.latest, endpointID: "e") { [Model(id: "b", created: 2)] }
        #expect(cached == .init(modelID: "a", isStale: false))

        let nextDay = ModelResolver(defaultsSuiteName: suite, now: { start.addingTimeInterval(ModelResolver.cacheLifetime + 1) })
        let refreshed = try await nextDay.resolve(.latest, endpointID: "e") { [Model(id: "b", created: 2)] }
        #expect(refreshed == .init(modelID: "b", isStale: false))

        let failing = ModelResolver(defaultsSuiteName: suite, now: { start.addingTimeInterval(3 * ModelResolver.cacheLifetime) })
        let stale = try await failing.resolve(.latest, endpointID: "e") { throw AIServiceError.unreachable }
        #expect(stale == .init(modelID: "b", isStale: true))
    }

    @Test func failsWithoutACachedModel() async {
        await #expect(throws: AIServiceError.unreachable) {
            try await makeResolver().resolve(.latest, endpointID: "e") { throw AIServiceError.unreachable }
        }
    }
}

struct OpenAIProtocolGeneratorTests {
    private let meeting = MeetingDetails(title: "Weekly sync", start: Date(timeIntervalSince1970: 1_800_000_000), attendees: ["Ada", "Bo"])
    private let notes = NoteDocument(blocks: [.listItem(ListItem(kind: .bulleted, text: "Decided to ship Friday"))])
    private let answer = #"{"language":"en","attendeesPresent":["Ada"],"attendeesAbsent":["Bo"],"agendaItems":[{"title":"Release","summary":"We discussed the release."}],"decisions":["Ship on Friday."],"actionItems":[{"task":"Write notes","owner":null,"dueDate":null}]}"#

    private func makeGenerator(_ transport: MockTransport) -> OpenAIProtocolGenerator {
        OpenAIProtocolGenerator(
            configuration: AIEndpointConfiguration(preset: .custom, baseURL: "https://example.com/v1", modelChoice: .specific("m")),
            apiKey: "k",
            transport: transport,
            modelResolver: ModelResolver(defaultsSuiteName: "NotesVTests-\(UUID().uuidString)"),
            outputSupport: StructuredOutputSupport()
        )
    }

    @Test func generatesAProtocol() async throws {
        let transport = MockTransport([MockTransport.chatReply(answer)])
        let result = try await makeGenerator(transport).generateProtocol(meeting: meeting, notes: notes, language: .automatic)

        #expect(result.modelID == "m")
        #expect(result.warning == nil)
        #expect(result.minutes.decisions == ["Ship on Friday."])
        #expect(result.minutes.actionItems == [.init(task: "Write notes", owner: nil, dueDate: nil)])

        guard case .array(let messages)? = transport.body(at: 0)["messages"], case .object(let user) = messages[1],
              case .string(let content)? = user["content"] else {
            Issue.record("Missing user message")
            return
        }
        #expect(content.contains("Title: Weekly sync"))
        #expect(content.contains("* Decided to ship Friday"))
    }

    @Test func fallsBackWhenTheServerRejectsJSONModes() async throws {
        let transport = MockTransport([
            .status(400, #"{"error":"json_schema not supported"}"#),
            .status(400, #"{"error":"json_object not supported"}"#),
            MockTransport.chatReply("Here you go:\n```json\n\(answer)\n```"),
        ])
        let result = try await makeGenerator(transport).generateProtocol(meeting: meeting, notes: notes, language: .english)

        #expect(result.minutes.agendaItems.first?.title == "Release")
        #expect(transport.requests.count == 3)
        #expect(transport.body(at: 1)["response_format"] == ["type": "json_object"])
        #expect(transport.body(at: 2)["response_format"] == nil)
    }

    @Test func doesNotRetryOtherErrors() async throws {
        let transport = MockTransport([.status(401, "{}")])
        await #expect(throws: AIServiceError.unauthorized) {
            try await makeGenerator(transport).generateProtocol(meeting: meeting, notes: notes, language: .automatic)
        }
        #expect(transport.requests.count == 1)
    }

    @Test func readsJSONAfterReasoning() throws {
        let minutes = try OpenAIProtocolGenerator.decodeProtocol(from: "<think>{not json}</think>\n\(answer)")
        #expect(minutes.language == "en")
        #expect(throws: AIServiceError.invalidResponse) {
            try OpenAIProtocolGenerator.decodeProtocol(from: "Sorry, I can't help with that.")
        }
    }

    @Test func toleratesMissingLists() throws {
        let minutes = try OpenAIProtocolGenerator.decodeProtocol(from: #"{"language":"sv","decisions":["A"]}"#)
        #expect(minutes == MeetingProtocol(language: "sv", decisions: ["A"]))
    }
}

struct ProtocolFormatterTests {
    @Test func writesAllSectionsWithPlaceholders() {
        let meeting = MeetingDetails(
            title: "Veckomöte",
            start: Date(timeIntervalSince1970: 1_792_486_800),
            end: Date(timeIntervalSince1970: 1_792_490_400),
            location: "Rum 1",
            organizer: "Ada"
        )
        let minutes = MeetingProtocol(
            language: "sv",
            attendeesPresent: ["Ada", "Bo"],
            agendaItems: [.init(title: "Release", summary: "Vi gick igenom releasen.")],
            actionItems: [.init(task: "Skriv notes", owner: "Bo", dueDate: nil)]
        )
        let document = ProtocolFormatter.document(for: minutes, meeting: meeting, timeZone: TimeZone(identifier: "UTC")!)

        #expect(document.title == "Protokoll – Veckomöte")
        let headings = document.blocks.compactMap { block -> String? in
            if case .paragraph(.heading, let text) = block { text.plainText } else { nil }
        }
        #expect(headings == ["Mötesinformation", "Deltagare", "Agenda och diskussion", "Beslut", "Åtgärdspunkter"])
        #expect(document.blocks.contains(.paragraph(.body, "Inga noterade")))
        #expect(document.blocks.last == .listItem(ListItem(kind: .checklist, text: "Skriv notes – Bo, [Datum saknas]")))
        #expect(document.blocks.contains(.listItem(ListItem(kind: .bulleted, text: RichText([
            TextRun("Plats:", style: .bold), TextRun(" Rum 1"),
        ])))))
    }

    @Test func usesEnglishForOtherLanguages() {
        let meeting = MeetingDetails(title: "Sync", start: .now)
        let document = ProtocolFormatter.document(for: MeetingProtocol(language: "de"), meeting: meeting)
        #expect(document.title == "Minutes – Sync")
    }
}

struct KeychainServiceTests {
    @Test func storesReadsAndDeletesPasswords() throws {
        let keychain = KeychainService(service: "se.consid.NotesV.tests.\(UUID().uuidString)")
        #expect(try keychain.password(for: "a") == nil)

        try keychain.setPassword("one", for: "a")
        try keychain.setPassword("two", for: "a")
        #expect(try keychain.password(for: "a") == "two")

        try keychain.setPassword(nil, for: "a")
        #expect(try keychain.password(for: "a") == nil)
    }
}
