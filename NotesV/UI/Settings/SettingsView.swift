import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsView()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 540)
    }
}

struct AISettingsView: View {
    @Environment(AISettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LabeledContent("Provider") {
                    Text("OpenAI-compatible API")
                }
                Text("Microsoft 365 Copilot will be added later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Server") {
                Picker("Preset", selection: Binding(
                    get: { settings.configuration.preset },
                    set: { settings.selectPreset($0) }
                )) {
                    ForEach(AIEndpointPreset.allCases, id: \.self) { preset in
                        PresetName(preset: preset).tag(preset)
                    }
                }
                TextField("Server address", text: $settings.configuration.baseURL, prompt: Text(verbatim: "https://…/v1"))
                    .textContentType(.URL)
                Picker("Key header", selection: $settings.configuration.authStyle) {
                    Text(verbatim: "Authorization: Bearer").tag(AuthHeaderStyle.bearer)
                    Text(verbatim: "api-key").tag(AuthHeaderStyle.apiKey)
                }
                SecureField(
                    "API key",
                    text: $settings.apiKey,
                    prompt: settings.configuration.isLocal ? Text("Optional") : Text("Required")
                )
            }

            Section("Model") {
                Picker("Model", selection: modelSelection) {
                    Text("Latest").tag(String?.none)
                    ForEach(modelOptions, id: \.self) { model in
                        Text(verbatim: model).tag(String?.some(model))
                    }
                }
                HStack {
                    Button("Test Connection") {
                        Task { await settings.testConnection() }
                    }
                    .disabled(settings.connectionStatus == .testing)
                    ConnectionStatusView(status: settings.connectionStatus)
                }
            }

            Section {
                Label {
                    if settings.configuration.isLocal {
                        Text("Meeting details and notes are sent to a server on this Mac and don’t leave it.")
                    } else {
                        Text("Meeting details and notes are sent to the server above. They leave your Microsoft 365 organization.")
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var modelSelection: Binding<String?> {
        Binding(
            get: {
                if case .specific(let model) = settings.configuration.modelChoice { model } else { nil }
            },
            set: { settings.configuration.modelChoice = $0.map(ModelChoice.specific) ?? .latest }
        )
    }

    /// The fetched models, plus the chosen one if it isn't in the list yet.
    private var modelOptions: [String] {
        var options = settings.availableModels
        if case .specific(let model) = settings.configuration.modelChoice, !options.contains(model) {
            options.insert(model, at: 0)
        }
        return options
    }
}

private struct PresetName: View {
    let preset: AIEndpointPreset

    var body: some View {
        switch preset {
        case .openAI: Text(verbatim: "OpenAI")
        case .azureOpenAI: Text(verbatim: "Azure OpenAI")
        case .openRouter: Text(verbatim: "OpenRouter")
        case .ollama: Text("Ollama (on this Mac)")
        case .lmStudio: Text("LM Studio (on this Mac)")
        case .custom: Text("Other OpenAI-compatible server")
        }
    }
}

private struct ConnectionStatusView: View {
    let status: AISettings.ConnectionStatus

    var body: some View {
        switch status {
        case .unknown:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .connected(let count):
            Label {
                Text("Connected. \(count) models available.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failed(let message):
            Label {
                Text(verbatim: message).lineLimit(3)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}
