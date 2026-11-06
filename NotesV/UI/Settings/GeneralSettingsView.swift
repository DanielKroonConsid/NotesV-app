import SwiftUI

/// Lets the user say what they are called in protocols.
struct GeneralSettingsView: View {
    @Environment(ProfileSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("My names", text: $settings.namesText, prompt: Text("Ada Ek, Ada"))
            } footer: {
                Text("Separate names with commas. New tasks with one of these names are set to you when you review them. The names stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
