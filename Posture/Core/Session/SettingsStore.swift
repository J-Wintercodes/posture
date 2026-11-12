import Foundation
import Observation
import SwiftUI

/// Persists `UserSettings` as JSON in UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    private(set) var value: UserSettings

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "posture.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            value = decoded
        } else {
            value = UserSettings()
        }
    }

    func update(_ mutate: (inout UserSettings) -> Void) {
        var copy = value
        mutate(&copy)
        value = copy
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: key)
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<UserSettings, T>) -> Binding<T> {
        Binding(
            get: { self.value[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
