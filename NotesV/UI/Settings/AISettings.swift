import Foundation
import Observation

/// The AI provider settings. The configuration is stored in `UserDefaults`, the API key in the Keychain.
@MainActor
@Observable
final class AISettings {
    enum ConnectionStatus: Equatable {
        case unknown
        case testing
        case connected(modelCount: Int)
        case failed(String)
    }

    var configuration: AIEndpointConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            saveConfiguration()
            if configuration.preset != oldValue.preset {
                loadAPIKey()
            }
            if configuration.endpointID != oldValue.endpointID || configuration.authStyle != oldValue.authStyle {
                availableModels = []
                connectionStatus = .unknown
            }
        }
    }

    /// The API key as typed in Settings. Saved to the Keychain on every change, except that an
    /// empty field never deletes the saved key: that takes `removeAPIKey()`, after the user confirms.
    var apiKey = "" {
        didSet {
            guard apiKey != oldValue, !isLoadingKey, !apiKey.isEmpty else { return }
            do {
                try keychain.setPassword(apiKey, for: keychainAccount)
                hasStoredKey = true
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    /// Whether the Keychain holds a key for this server, even while the field is empty.
    private(set) var hasStoredKey = false

    /// The key requests use: the one typed, or the saved one while the field is empty.
    private var effectiveAPIKey: String {
        guard apiKey.isEmpty, hasStoredKey else { return apiKey }
        return (try? keychain.password(for: keychainAccount)) ?? ""
    }

    func removeAPIKey() {
        do {
            try keychain.setPassword(nil, for: keychainAccount)
            hasStoredKey = false
            isLoadingKey = true
            apiKey = ""
            isLoadingKey = false
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private(set) var availableModels: [String] = []
    private(set) var connectionStatus = ConnectionStatus.unknown

    /// Called when the configuration has changed, so it can be backed up.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let keychain: KeychainService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let modelResolver: ModelResolver
    @ObservationIgnored private var isLoadingKey = false
    private static let configurationKey = "ai.endpointConfiguration"

    init(keychain: KeychainService = KeychainService(), defaultsSuiteName: String? = nil) {
        self.keychain = keychain
        defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        modelResolver = ModelResolver(defaultsSuiteName: defaultsSuiteName)
        configuration = defaults.data(forKey: Self.configurationKey)
            .flatMap { try? JSONDecoder().decode(AIEndpointConfiguration.self, from: $0) } ?? .default
        loadAPIKey()
    }

    /// One key per preset, so editing the server address doesn't lose the key.
    private var keychainAccount: String {
        configuration.preset.rawValue
    }

    func selectPreset(_ preset: AIEndpointPreset) {
        guard preset != configuration.preset else { return }
        configuration = AIEndpointConfiguration(preset: preset)
    }

    /// Lists the server's models, which also checks the address and key.
    func testConnection() async {
        connectionStatus = .testing
        do {
            let client = try OpenAICompatibleClient(configuration: configuration, apiKey: effectiveAPIKey, transport: URLSessionTransport())
            let models = try await client.listModels()
            availableModels = models.map(\.id).sorted()
            connectionStatus = .connected(modelCount: models.count)
            await modelResolver.clearCache(for: configuration.endpointID)
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    func makeGenerator() throws -> any ProtocolGenerator {
        _ = try configuration.validatedBaseURL()
        return OpenAIProtocolGenerator(
            configuration: configuration,
            apiKey: effectiveAPIKey.isEmpty ? nil : effectiveAPIKey,
            modelResolver: modelResolver
        )
    }

    private func loadAPIKey() {
        isLoadingKey = true
        defer { isLoadingKey = false }
        do {
            apiKey = try keychain.password(for: keychainAccount) ?? ""
            hasStoredKey = !apiKey.isEmpty
        } catch {
            apiKey = ""
            hasStoredKey = false
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func saveConfiguration() {
        defaults.set(try? JSONEncoder().encode(configuration), forKey: Self.configurationKey)
        onChange?()
    }
}
