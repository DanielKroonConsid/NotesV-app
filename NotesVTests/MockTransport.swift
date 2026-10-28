import Foundation
import Synchronization
@testable import NotesV

/// An `HTTPTransport` that returns canned replies and records every request.
final class MockTransport: HTTPTransport {
    enum Reply {
        case status(Int, String)
        case failure(URLError)
    }

    private struct State {
        var replies: [Reply]
        var requests: [URLRequest] = []
    }

    private let state: Mutex<State>

    init(_ replies: [Reply]) {
        state = Mutex(State(replies: replies))
    }

    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    /// The JSON body of the request at `index`.
    func body(at index: Int) -> [String: JSONValue] {
        guard let data = requests[index].httpBody,
              case .object(let body)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        return body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = state.withLock { state -> Reply in
            state.requests.append(request)
            return state.replies.isEmpty ? .status(500, "{}") : state.replies.removeFirst()
        }
        switch reply {
        case .status(let code, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        case .failure(let error):
            throw error
        }
    }

    /// A chat completion response whose answer is `content`.
    static func chatReply(_ content: String) -> Reply {
        let body: JSONValue = ["choices": [["message": ["role": "assistant", "content": .string(content)]]]]
        return .status(200, String(decoding: try! JSONEncoder().encode(body), as: UTF8.self))
    }
}
