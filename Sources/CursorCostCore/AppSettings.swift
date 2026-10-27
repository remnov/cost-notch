import Combine
import Foundation

@MainActor
public final class AppSettings: ObservableObject {
    public static let storageKey = "costNotch.preferences"
    public static let lastAlertKey = "costNotch.lastAlertedQuery"

    @Published public var preferences: NotchPreferences {
        didSet { persist() }
    }

    @Published public var lastAlertedQueryKey: String {
        didSet { UserDefaults.standard.set(lastAlertedQueryKey, forKey: Self.lastAlertKey) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey)
            ?? defaults.data(forKey: "cursorNotch.preferences"),
           var loaded = try? JSONDecoder().decode(NotchPreferences.self, from: data)
        {
            loaded.clamp()
            self.preferences = loaded
        } else {
            self.preferences = .standard
        }
        self.lastAlertedQueryKey = defaults.string(forKey: Self.lastAlertKey) ?? ""
    }

    public func reset() {
        preferences = .standard
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
