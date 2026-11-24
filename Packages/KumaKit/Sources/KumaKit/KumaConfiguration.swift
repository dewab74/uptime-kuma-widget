import Foundation

/// Which status page to mirror and how often to ask.
public struct KumaConfiguration: Codable, Sendable, Equatable {
    /// Root of the Uptime Kuma server, e.g. `https://status.example.com`.
    public var baseURL: URL
    /// Status page slug, the last path part of `/status/<slug>`.
    public var slug: String
    /// Seconds between polls. Kuma caches the heartbeat API for 60 s.
    public var pollInterval: TimeInterval

    public static let minimumPollInterval: TimeInterval = 30
    public static let defaultPollInterval: TimeInterval = 60

    public init(baseURL: URL, slug: String, pollInterval: TimeInterval = Self.defaultPollInterval) {
        self.baseURL = baseURL
        self.slug = slug.lowercased()
        self.pollInterval = max(pollInterval, Self.minimumPollInterval)
    }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case invalidURL
        case unsupportedScheme
        case invalidSlug

        public var errorDescription: String? {
            switch self {
            case .invalidURL: "Enter the server address, like https://status.example.com."
            case .unsupportedScheme: "The address must start with http:// or https://."
            case .invalidSlug: "The slug may contain only letters, digits and dashes."
            }
        }
    }

    /// Parses what a person types. Accepts a pasted status page link
    /// (`https://host/status/home`) and takes the slug from it when `slug` is blank.
    public static func parse(
        address: String, slug: String, pollInterval: TimeInterval = defaultPollInterval
    ) throws(ValidationError) -> KumaConfiguration {
        var address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "https://" + address }
        guard var components = URLComponents(string: address), let host = components.host, !host.isEmpty else {
            throw .invalidURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw .unsupportedScheme
        }
        var parts = components.path.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[parts.count - 2] == "status" {
            if slug.isEmpty { slug = parts[parts.count - 1] }
            parts.removeLast(2)
        }
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw .invalidURL }
        if slug.isEmpty { slug = "default" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard slug.unicodeScalars.allSatisfy(allowed.contains) else { throw .invalidSlug }
        return KumaConfiguration(baseURL: url, slug: slug, pollInterval: pollInterval)
    }

    private func appending(_ path: String) -> URL {
        baseURL.appending(path: path, directoryHint: .notDirectory)
    }

    public var pageAPIURL: URL { appending("api/status-page/\(slug)") }
    public var heartbeatAPIURL: URL { appending("api/status-page/heartbeat/\(slug)") }
    /// The human status page, opened when the widget is clicked.
    public var statusPageURL: URL { appending("status/\(slug)") }
}
