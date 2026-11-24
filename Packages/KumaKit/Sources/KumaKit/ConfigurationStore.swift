import Foundation

/// The App Group both targets share, read from the `KumaAppGroup` key that
/// the build writes into each Info.plist (team id prefix included).
public enum AppGroup {
    public static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "KumaAppGroup") as? String) ?? ""
    }

    public static var stateStore: SharedStateStore? { SharedStateStore(appGroup: identifier) }

    public static var configurationStore: ConfigurationStore {
        ConfigurationStore(defaults: UserDefaults(suiteName: identifier.isEmpty ? nil : identifier) ?? .standard)
    }
}

/// Persists the `KumaConfiguration` in the shared defaults, so the widget can
/// fetch on its own when the app is not running.
public struct ConfigurationStore: @unchecked Sendable {
    // UserDefaults is documented thread-safe; it is just not marked Sendable.
    private let defaults: UserDefaults
    static let key = "configuration"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> KumaConfiguration? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(KumaConfiguration.self, from: data)
    }

    public func save(_ configuration: KumaConfiguration?) {
        if let configuration, let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
