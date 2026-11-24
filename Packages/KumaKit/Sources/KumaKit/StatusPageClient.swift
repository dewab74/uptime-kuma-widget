import Foundation

public enum FetchError: Error, Equatable, LocalizedError {
    /// The server answered, but there is no published page with that slug.
    case pageNotFound(slug: String)
    case http(status: Int)
    /// The answer was not Uptime Kuma's JSON (a login page, a proxy error page).
    case notKuma
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .pageNotFound(let slug): "No status page \"\(slug)\" on this server."
        case .http(let status): "The server answered HTTP \(status)."
        case .notKuma: "The server did not answer like Uptime Kuma."
        case .transport(let message): message
        }
    }
}

/// Reads a status page through Kuma's public, unauthenticated API: the same
/// two requests the web status page makes.
public struct StatusPageClient: Sendable {
    private let session: URLSession
    private let now: @Sendable () -> Date

    public static let requestTimeout: TimeInterval = 15

    public init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    public func fetch(_ configuration: KumaConfiguration) async throws(FetchError) -> StatusSnapshot {
        do {
            async let page: StatusPageAPI.Page = get(configuration.pageAPIURL, slug: configuration.slug)
            async let beats: StatusPageAPI.Heartbeats = get(configuration.heartbeatAPIURL, slug: configuration.slug)
            return try await StatusPageAPI.makeSnapshot(
                page: page, beats: beats, pageURL: configuration.statusPageURL, fetchedAt: now())
        } catch let error as FetchError {
            throw error
        } catch {
            throw .transport(error.localizedDescription)
        }
    }

    private func get<T: Decodable>(_ url: URL, slug: String) async throws -> T {
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FetchError.transport(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Kuma answers an unknown slug with 404 and {"ok":false,"msg":"..."}.
        // The heartbeat endpoint answers an unknown slug with empty lists.
        if status == 404 { throw FetchError.pageNotFound(slug: slug) }
        guard (200..<300).contains(status) else { throw FetchError.http(status: status) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FetchError.notKuma
        }
    }
}
