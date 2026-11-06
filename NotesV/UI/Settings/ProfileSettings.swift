import Foundation
import Observation

/// What the app knows about the user. Stored in `UserDefaults`, on this Mac only.
@MainActor
@Observable
final class ProfileSettings {
    /// The names the user goes by in protocols, separated by commas.
    var namesText: String {
        didSet { defaults.set(namesText, forKey: Self.namesKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let namesKey = "profile.names"

    init(defaultsSuiteName: String? = nil) {
        defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        namesText = defaults.string(forKey: Self.namesKey) ?? ""
    }

    var names: [String] {
        namesText
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
