import Foundation

/// How the API key is sent to the server.
enum AuthHeaderStyle: String, CaseIterable, Codable, Hashable, Sendable {
    /// `Authorization: Bearer <key>` (OpenAI, OpenRouter, most servers).
    case bearer
    /// `api-key: <key>` (Azure OpenAI).
    case apiKey
}

/// Ready-made settings for common OpenAI-compatible servers.
enum AIEndpointPreset: String, CaseIterable, Codable, Hashable, Sendable {
    case openAI
    case azureOpenAI
    case openRouter
    case ollama
    case lmStudio
    case custom

    var baseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .azureOpenAI: "https://YOUR-RESOURCE.openai.azure.com/openai/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .custom: ""
        }
    }

    var authStyle: AuthHeaderStyle {
        self == .azureOpenAI ? .apiKey : .bearer
    }
}

/// Which model to use.
enum ModelChoice: Codable, Hashable, Sendable {
    /// The newest text model the server offers (see `ModelResolver`).
    case latest
    case specific(String)
}

/// The settings for one OpenAI-compatible server. Stored in `UserDefaults`; the API key is not
/// part of it and lives in the Keychain.
struct AIEndpointConfiguration: Codable, Hashable, Sendable {
    var preset: AIEndpointPreset
    var baseURL: String
    var authStyle: AuthHeaderStyle
    var modelChoice: ModelChoice

    init(preset: AIEndpointPreset, baseURL: String? = nil, authStyle: AuthHeaderStyle? = nil, modelChoice: ModelChoice = .latest) {
        self.preset = preset
        self.baseURL = baseURL ?? preset.baseURL
        self.authStyle = authStyle ?? preset.authStyle
        self.modelChoice = modelChoice
    }

    static let `default` = AIEndpointConfiguration(preset: .openAI)

    /// Identifies the server, e.g. for its Keychain entry and model cache.
    var endpointID: String {
        (try? validatedBaseURL().absoluteString) ?? baseURL
    }

    /// Whether data stays on this Mac.
    var isLocal: Bool {
        (try? validatedBaseURL()).flatMap(\.host).map(Self.isLocalHost) ?? false
    }

    /// The base URL without a trailing slash. Plain `http` is only allowed for local servers.
    func validatedBaseURL() throws(AIServiceError) -> URL {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host(), !host.isEmpty else {
            throw .invalidBaseURL
        }
        switch scheme {
        case "https":
            return url
        case "http" where Self.isLocalHost(host):
            return url
        case "http":
            throw .insecureBaseURL
        default:
            throw .invalidBaseURL
        }
    }

    static func isLocalHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" || host.hasSuffix(".local")
    }
}
