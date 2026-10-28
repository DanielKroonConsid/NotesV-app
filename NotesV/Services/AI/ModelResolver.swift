import Foundation

/// Picks the model to use. "Latest" means the newest text model the server offers, looked up at
/// most once a day per server.
actor ModelResolver {
    struct Resolution: Hashable, Sendable {
        var modelID: String
        /// `true` if the lookup failed and an older cached model is used.
        var isStale: Bool
    }

    private struct CacheEntry: Codable {
        var modelID: String
        var resolvedAt: Date
    }

    static let cacheLifetime: TimeInterval = 24 * 60 * 60

    /// Parts of model ids that mark models which can't write text (embeddings, audio, images and so on).
    private static let nonTextMarkers = [
        "embed", "whisper", "tts", "audio", "dall-e", "image", "moderation", "realtime",
        "transcribe", "search", "rerank", "sora",
    ]

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    /// - Parameter defaultsSuiteName: The `UserDefaults` suite for the cache; `nil` for the standard one.
    init(defaultsSuiteName: String? = nil, now: @escaping @Sendable () -> Date = { .now }) {
        defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.now = now
    }

    func resolve(
        _ choice: ModelChoice,
        endpointID: String,
        listModels: @Sendable () async throws -> [OpenAICompatibleClient.Model]
    ) async throws -> Resolution {
        if case .specific(let modelID) = choice {
            return Resolution(modelID: modelID, isStale: false)
        }

        let cached = cacheEntry(for: endpointID)
        if let cached, now().timeIntervalSince(cached.resolvedAt) < Self.cacheLifetime {
            return Resolution(modelID: cached.modelID, isStale: false)
        }

        do {
            let modelID = try Self.latestTextModel(in: try await listModels())
            store(CacheEntry(modelID: modelID, resolvedAt: now()), for: endpointID)
            return Resolution(modelID: modelID, isStale: false)
        } catch let error as AIServiceError where error == .modelSelectionRequired {
            throw error
        } catch {
            guard let cached else { throw error }
            return Resolution(modelID: cached.modelID, isStale: true)
        }
    }

    /// The newest model by creation date. Servers that don't report dates must offer exactly one
    /// text model, otherwise the user has to choose.
    static func latestTextModel(in models: [OpenAICompatibleClient.Model]) throws(AIServiceError) -> String {
        let textModels = models.filter { model in
            let id = model.id.lowercased()
            return !nonTextMarkers.contains { id.contains($0) }
        }
        let dated = textModels.filter { ($0.created ?? 0) > 0 }
        if let newest = dated.max(by: { ($0.created!, $0.id) < ($1.created!, $1.id) }) {
            return newest.id
        }
        if textModels.count == 1 {
            return textModels[0].id
        }
        throw .modelSelectionRequired
    }

    func clearCache(for endpointID: String) {
        defaults.removeObject(forKey: Self.cacheKey(for: endpointID))
    }

    private func cacheEntry(for endpointID: String) -> CacheEntry? {
        guard let data = defaults.data(forKey: Self.cacheKey(for: endpointID)) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    private func store(_ entry: CacheEntry, for endpointID: String) {
        defaults.set(try? JSONEncoder().encode(entry), forKey: Self.cacheKey(for: endpointID))
    }

    private static func cacheKey(for endpointID: String) -> String {
        "ai.latestModel.\(endpointID)"
    }
}
