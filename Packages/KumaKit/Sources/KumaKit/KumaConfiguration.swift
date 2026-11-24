import Foundation

/// Which status page to mirror and how often to ask.
public struct KumaConfiguration: Codable, Sendable, Equatable {
    /// Root of the Uptime Kuma server, e.g. `https://status.example.com`.
    public var baseURL: URL
    /// Status page slug, the last path part of `/status/<slug>`.
    public var slug: String
    /// Seconds between polls. Kuma caches the heartbeat API for 60 s.
    public var pollInterval: TimeInterval
    /// Check the server's TLS certificate (default). When false, any
    /// certificate the configured host presents is accepted, for a Kuma behind
    /// a self-signed or private-CA certificate. The connection stays encrypted.
    public var verifyCertificate: Bool

    public static let minimumPollInterval: TimeInterval = 30
    public static let defaultPollInterval: TimeInterval = 60

    public init(
        baseURL: URL, slug: String, pollInterval: TimeInterval = Self.defaultPollInterval,
        verifyCertificate: Bool = true
    ) {
        self.baseURL = baseURL
        self.slug = slug.lowercased()
        self.pollInterval = max(pollInterval, Self.minimumPollInterval)
        self.verifyCertificate = verifyCertificate
    }

    // Settings saved before `verifyCertificate` existed decode with it on.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            baseURL: try container.decode(URL.self, forKey: .baseURL),
            slug: try container.decode(String.self, forKey: .slug),
            pollInterval: try container.decode(TimeInterval.self, forKey: .pollInterval),
            verifyCertificate: try container.decodeIfPresent(Bool.self, forKey: .verifyCertificate) ?? true)
    }

    /// The host certificate checks are skipped for, when they are.
    public var host: String { baseURL.host() ?? "" }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case invalidURL
        case unsupportedScheme
        case invalidPort
        case invalidSlug

        public var errorDescription: String? {
            switch self {
            case .invalidURL: "Enter the URL of your Uptime Kuma, like https://status.example.com:3001."
            case .unsupportedScheme: "The URL must start with http:// or https://."
            case .invalidPort: "The port must be a number from 1 to 65535."
            case .invalidSlug: "The slug may contain only letters, digits and dashes."
            }
        }
    }

    /// Parses what a person types. Accepts a pasted status page link
    /// (`https://host/status/home`) and takes the slug from it when `slug` is
    /// blank. A port (`http://kuma.lan:3001`, `[fd00::5]:3001`) is kept, and
    /// with no scheme `https://` is assumed.
    public static func parse(
        address: String, slug: String, pollInterval: TimeInterval = defaultPollInterval,
        verifyCertificate: Bool = true
    ) throws(ValidationError) -> KumaConfiguration {
        var address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.contains("://") { address = "https://" + address }
        // URLComponents refuses a URL whose port is not a number; say why.
        if URLComponents(string: address) == nil, Self.hasNonNumericPort(address) { throw .invalidPort }
        guard var components = URLComponents(string: address), let host = components.host, !host.isEmpty else {
            throw .invalidURL
        }
        if let port = components.port, !(1...65535).contains(port) { throw .invalidPort }
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
        return KumaConfiguration(
            baseURL: url, slug: slug, pollInterval: pollInterval, verifyCertificate: verifyCertificate)
    }

    /// `host:` followed by something other than digits, in the authority.
    private static func hasNonNumericPort(_ address: String) -> Bool {
        guard let start = address.range(of: "://")?.upperBound else { return false }
        let authority = address[start...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let hostAndPort = authority.split(separator: "@").last ?? ""
        let afterHost =
            hostAndPort.hasPrefix("[") ? hostAndPort.split(separator: "]").dropFirst().first ?? "" : hostAndPort
        guard let colon = afterHost.lastIndex(of: ":") else { return false }
        let port = afterHost[afterHost.index(after: colon)...]
        return !port.isEmpty && !port.allSatisfy(\.isNumber)
    }

    private func appending(_ path: String) -> URL {
        baseURL.appending(path: path, directoryHint: .notDirectory)
    }

    public var pageAPIURL: URL { appending("api/status-page/\(slug)") }
    public var heartbeatAPIURL: URL { appending("api/status-page/heartbeat/\(slug)") }
    /// The human status page, opened when the widget is clicked.
    public var statusPageURL: URL { appending("status/\(slug)") }
}
