import Foundation

/// Talks to any server that implements OpenAI's `/models` and `/chat/completions` endpoints:
/// OpenAI, Azure OpenAI, OpenRouter, Ollama, LM Studio and others.
struct OpenAICompatibleClient: Sendable {
    struct Model: Decodable, Hashable, Sendable {
        var id: String
        /// Unix time when the model was created. Some local servers leave it out.
        var created: Int?
    }

    struct Message: Hashable, Sendable {
        var role: String
        var content: String

        static func system(_ content: String) -> Message { Message(role: "system", content: content) }
        static func user(_ content: String) -> Message { Message(role: "user", content: content) }
    }

    enum ResponseFormat: Hashable, Sendable {
        /// Structured output that must match the schema. The most reliable, but not every server supports it.
        case jsonSchema(name: String, schema: JSONValue)
        /// Any JSON object.
        case jsonObject
        /// Plain text; the JSON is extracted from the answer.
        case text
    }

    private let baseURL: URL
    private let apiKey: String?
    private let authStyle: AuthHeaderStyle
    private let transport: any HTTPTransport

    init(configuration: AIEndpointConfiguration, apiKey: String?, transport: any HTTPTransport) throws(AIServiceError) {
        baseURL = try configuration.validatedBaseURL()
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        authStyle = configuration.authStyle
        self.transport = transport
    }

    func listModels() async throws -> [Model] {
        struct Response: Decodable {
            var data: [Model]
        }
        let data = try await perform(makeRequest(path: "models", method: "GET"))
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIServiceError.invalidResponse
        }
        return response.data
    }

    /// Returns the text of the first answer.
    func chatCompletion(model: String, messages: [Message], responseFormat: ResponseFormat) async throws -> String {
        // No `temperature`: some reasoning models reject anything but the default.
        var body: [String: JSONValue] = [
            "model": .string(model),
            "messages": .array(messages.map { ["role": .string($0.role), "content": .string($0.content)] }),
        ]
        switch responseFormat {
        case .jsonSchema(let name, let schema):
            body["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": .string(name), "strict": true, "schema": schema],
            ]
        case .jsonObject:
            body["response_format"] = ["type": "json_object"]
        case .text:
            break
        }

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    var content: String?
                }
                var message: Message
            }
            var choices: [Choice]
        }
        let data = try await perform(makeRequest(path: "chat/completions", method: "POST", body: .object(body)))
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let content = response.choices.first?.message.content,
              !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }

    // MARK: - Requests

    private func makeRequest(path: String, method: String, body: JSONValue? = nil) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            switch authStyle {
            case .bearer: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .apiKey: request.setValue(apiKey, forHTTPHeaderField: "api-key")
            }
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw AIServiceError.from(error) ?? error
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AIServiceError.from(status: response.statusCode, message: Self.errorMessage(in: data))
        }
        return data
    }

    /// Reads the error message from OpenAI-style (`{"error": {"message": …}}`) and
    /// Ollama-style (`{"error": "…"}`) error bodies.
    static func errorMessage(in data: Data) -> String? {
        guard case .object(let body)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        switch body["error"] {
        case .string(let message)?:
            return message
        case .object(let error)?:
            if case .string(let message)? = error["message"] { return message }
        default:
            break
        }
        if case .string(let message)? = body["message"] { return message }
        return nil
    }
}
