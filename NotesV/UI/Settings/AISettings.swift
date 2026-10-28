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

    /// The API key as typed in Settings. Saved to the Keychain on every change.
    var apiKey = "" {
        didSet {
            guard apiKey != oldValue, !isLoadingKey else { return }
            do {
                try keychain.setPassword(apiKey, for: keychainAccount)
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
        }
    }

    private(set) var availableModels: [String] = []
    private(set) var connectionStatus = ConnectionStatus.unknown

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
            let client = try OpenAICompatibleClient(configuration: configuration, apiKey: apiKey, transport: URLSessionTransport())
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
            apiKey: apiKey.isEmpty ? nil : apiKey,
            modelResolver: modelResolver
        )
    }

    private func loadAPIKey() {
        isLoadingKey = true
        defer { isLoadingKey = false }
        do {
            apiKey = try keychain.password(for: keychainAccount) ?? ""
        } catch {
            apiKey = ""
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func saveConfiguration() {
        defaults.set(try? JSONEncoder().encode(configuration), forKey: Self.configurationKey)
    }
}
