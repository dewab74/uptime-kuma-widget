import Foundation

public enum FetchError: Error, Equatable, LocalizedError {
    /// The server answered, but there is no published page with that slug.
    case pageNotFound(slug: String)
    case http(status: Int)
    /// The answer was not Uptime Kuma's JSON (a login page, a proxy error page).
    case notKuma
    /// TLS failed on the certificate: self-signed, expired, private CA.
    case certificate(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .pageNotFound(let slug): "No status page \"\(slug)\" on this server."
        case .http(let status): "The server answered HTTP \(status)."
        case .notKuma: "The server did not answer like Uptime Kuma."
        case .certificate(let message):
            "\(message) For a self-signed or private-CA certificate, turn off Verify TLS certificate."
        case .transport(let message): message
        }
    }
}

/// Reads a status page through Kuma's public, unauthenticated API: the same
/// two requests the web status page makes.
public struct StatusPageClient: Sendable {
    /// Set by tests; otherwise each fetch picks a session for its configuration.
    private let session: URLSession?
    private let now: @Sendable () -> Date

    public static let requestTimeout: TimeInterval = 15

    public init(session: URLSession? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    public func fetch(_ configuration: KumaConfiguration) async throws(FetchError) -> StatusSnapshot {
        let session =
            session ?? (configuration.verifyCertificate ? .shared : UnverifiedTLS.session(for: configuration.host))
        do {
            async let page: StatusPageAPI.Page = get(
                configuration.pageAPIURL, slug: configuration.slug, session: session)
            async let beats: StatusPageAPI.Heartbeats = get(
                configuration.heartbeatAPIURL, slug: configuration.slug, session: session)
            return try await StatusPageAPI.makeSnapshot(
                page: page, beats: beats, pageURL: configuration.statusPageURL, fetchedAt: now())
        } catch let error as FetchError {
            throw error
        } catch {
            throw .transport(error.localizedDescription)
        }
    }

    private func get<T: Decodable>(_ url: URL, slug: String, session: URLSession) async throws -> T {
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.certificateErrors.contains(error.code) {
            throw FetchError.certificate(error.localizedDescription)
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

    static let certificateErrors: Set<URLError.Code> = [
        .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
        .serverCertificateHasUnknownRoot, .clientCertificateRejected, .secureConnectionFailed,
    ]
}

/// Sessions that skip certificate checks, for `verifyCertificate == false`.
/// Each accepts an unverifiable certificate only from its own host, so a
/// redirect to anywhere else is still checked normally. One session per host
/// is kept for the life of the process: URLSession holds its delegate strongly,
/// and a new session every poll would leak.
enum UnverifiedTLS {
    nonisolated(unsafe) private static var sessions: [String: URLSession] = [:]
    private static let lock = NSLock()

    static func session(for host: String) -> URLSession {
        lock.withLock {
            if let session = sessions[host] { return session }
            let session = URLSession(
                configuration: .ephemeral, delegate: TrustHostDelegate(host: host), delegateQueue: nil)
            sessions[host] = session
            return session
        }
    }

    /// Whether to accept the server's certificate without evaluating it.
    static func accepts(authenticationMethod: String, challengeHost: String, configuredHost: String) -> Bool {
        authenticationMethod == NSURLAuthenticationMethodServerTrust
            && challengeHost.caseInsensitiveCompare(configuredHost) == .orderedSame
    }

    final class TrustHostDelegate: NSObject, URLSessionDelegate, Sendable {
        let host: String

        init(host: String) {
            self.host = host
        }

        func urlSession(
            _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            let space = challenge.protectionSpace
            guard
                UnverifiedTLS.accepts(
                    authenticationMethod: space.authenticationMethod, challengeHost: space.host, configuredHost: host),
                let trust = space.serverTrust
            else { return (.performDefaultHandling, nil) }
            return (.useCredential, URLCredential(trust: trust))
        }
    }
}
