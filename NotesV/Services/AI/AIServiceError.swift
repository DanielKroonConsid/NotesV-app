import Foundation

enum AIServiceError: LocalizedError, Equatable {
    case invalidBaseURL
    case insecureBaseURL
    case unauthorized
    case notFound
    case rateLimited
    case badRequest(String?)
    case server(status: Int, message: String?)
    case unreachable
    case invalidResponse
    case modelSelectionRequired
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            String(localized: "The server address isn’t a valid URL.")
        case .insecureBaseURL:
            String(localized: "Use https. Plain http is only allowed for servers on this Mac (localhost).")
        case .unauthorized:
            String(localized: "The server didn’t accept the API key. Check the key in Settings.")
        case .notFound:
            String(localized: "The server couldn’t find the address or the model. Check the server address and model in Settings.")
        case .rateLimited:
            String(localized: "Too many requests or no credits left. Wait a moment and try again.")
        case .badRequest(let message):
            message.map { String(localized: "The server rejected the request: \($0)") }
                ?? String(localized: "The server rejected the request.")
        case .server(let status, let message):
            message.map { String(localized: "The server returned an error (\(status)): \($0)") }
                ?? String(localized: "The server returned an error (\(status)).")
        case .unreachable:
            String(localized: "Couldn’t reach the server. Check your internet connection, or that Ollama or LM Studio is running.")
        case .invalidResponse:
            String(localized: "The model’s answer couldn’t be read as a protocol. Try again or choose another model.")
        case .modelSelectionRequired:
            String(localized: "The server offers several models. Choose one in Settings.")
        case .notConfigured:
            String(localized: "Set up an AI provider in Settings first.")
        }
    }

    /// Maps an HTTP status code and the server's error message to an error.
    static func from(status: Int, message: String?) -> AIServiceError {
        switch status {
        case 401, 403: .unauthorized
        case 404: .notFound
        case 429: .rateLimited
        case 400, 422: .badRequest(message)
        default: .server(status: status, message: message)
        }
    }

    /// Maps a networking error to an error, or returns `nil` if it isn't one we translate.
    static func from(_ error: URLError) -> AIServiceError? {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .timedOut,
             .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
            .unreachable
        default:
            nil
        }
    }
}
