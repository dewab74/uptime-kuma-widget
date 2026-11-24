import Foundation
import Testing

@testable import KumaKit

/// Serves canned answers keyed by URL path. Each test registers its own
/// routes under a unique host, so the suite can run in parallel.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Answer: Sendable {
        var status: Int
        var body: Data
    }

    nonisolated(unsafe) private static var routes: [String: Answer] = [:]
    private static let lock = NSLock()

    static func register(host: String, path: String, status: Int = 200, body: Data) {
        lock.withLock { routes[host + path] = Answer(status: status, body: body) }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let key = (url.host ?? "") + url.path
        let answer = Self.lock.withLock { Self.routes[key] }
        guard let answer else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite struct StatusPageClientTests {
    let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func client() -> StatusPageClient {
        let fetchedAt = fetchedAt
        return StatusPageClient(session: StubProtocol.session(), now: { fetchedAt })
    }

    @Test func decodesAPageWithGroupsHeartbeatsAndUptime() async throws {
        let host = "decode.test"
        StubProtocol.register(host: host, path: "/api/status-page/home", body: try fixture("page"))
        StubProtocol.register(host: host, path: "/api/status-page/heartbeat/home", body: try fixture("heartbeat"))
        let configuration = KumaConfiguration(baseURL: URL(string: "https://\(host)")!, slug: "home")

        let snapshot = try await client().fetch(configuration)

        #expect(snapshot.title == "Home Lab")
        #expect(snapshot.pageURL.absoluteString == "https://decode.test/status/home")
        #expect(snapshot.fetchedAt == fetchedAt)
        #expect(snapshot.incident == "Storage maintenance overran")
        #expect(snapshot.maintenance == ["NAS firmware"])
        #expect(snapshot.groups.map(\.name) == ["Network", "Apps"])
        // DNS is in both groups; the flat list has it once.
        #expect(snapshot.monitors.map(\.name) == ["Router", "DNS", "Home Assistant", "Plex"])

        let router = snapshot.monitors[0]
        #expect(router.status == .up)
        #expect(router.ping == 2.5)
        #expect(router.uptime24h == 1)
        #expect(router.history == [.up, .up])
        #expect(abs((router.lastCheck?.timeIntervalSince1970 ?? 0) - 1_795_512_540.456) < 0.001)

        let dns = snapshot.monitors[1]
        #expect(dns.status == .down)
        #expect(dns.ping == nil)
        #expect(dns.lastCheck == Date(timeIntervalSince1970: 1_795_512_570))

        #expect(snapshot.monitors[2].status == .pending)
        #expect(snapshot.monitors[3].status == .unknown)
        #expect(snapshot.monitors[3].uptime24h == nil)

        #expect(snapshot.summary.down == 1)
        #expect(snapshot.summary.overall == .partialOutage)
        #expect(snapshot.monitorsByUrgency.map(\.name) == ["DNS", "Home Assistant", "Plex", "Router"])
    }

    @Test func readsTheSingleIncidentOfKuma1() async throws {
        let host = "v1.test"
        StubProtocol.register(host: host, path: "/kuma/api/status-page/default", body: try fixture("page-v1"))
        StubProtocol.register(
            host: host, path: "/kuma/api/status-page/heartbeat/default",
            body: Data(#"{"heartbeatList":{"10":[{"status":3,"time":"2026-11-24 09:00:00","ping":null}]}}"#.utf8))
        let configuration = try KumaConfiguration.parse(address: "https://\(host)/kuma/status/default", slug: "")

        let snapshot = try await client().fetch(configuration)

        #expect(snapshot.incident == "Upstream ISP outage")
        #expect(snapshot.monitors.first?.status == .maintenance)
        #expect(snapshot.summary.overall == .maintenance)
    }

    @Test func reportsAnUnknownSlug() async throws {
        let host = "missing.test"
        let body = Data(#"{"ok":false,"msg":"Status Page Not Found"}"#.utf8)
        StubProtocol.register(host: host, path: "/api/status-page/nope", status: 404, body: body)
        StubProtocol.register(
            host: host, path: "/api/status-page/heartbeat/nope", body: Data(#"{"heartbeatList":{}}"#.utf8))
        let configuration = KumaConfiguration(baseURL: URL(string: "https://\(host)")!, slug: "nope")

        await #expect(throws: FetchError.pageNotFound(slug: "nope")) { try await client().fetch(configuration) }
    }

    @Test func reportsAnAnswerThatIsNotKuma() async throws {
        let host = "proxy.test"
        let html = Data("<html>Sign in</html>".utf8)
        StubProtocol.register(host: host, path: "/api/status-page/home", body: html)
        StubProtocol.register(host: host, path: "/api/status-page/heartbeat/home", body: html)
        let configuration = KumaConfiguration(baseURL: URL(string: "https://\(host)")!, slug: "home")

        await #expect(throws: FetchError.notKuma) { try await client().fetch(configuration) }
    }

    @Test func reportsAServerError() async throws {
        let host = "error.test"
        StubProtocol.register(host: host, path: "/api/status-page/home", status: 502, body: Data())
        StubProtocol.register(host: host, path: "/api/status-page/heartbeat/home", status: 502, body: Data())
        let configuration = KumaConfiguration(baseURL: URL(string: "https://\(host)")!, slug: "home")

        await #expect(throws: FetchError.http(status: 502)) { try await client().fetch(configuration) }
    }

    @Test func reportsAnUnreachableServer() async throws {
        let configuration = KumaConfiguration(baseURL: URL(string: "https://unreachable.test")!, slug: "home")
        do {
            _ = try await client().fetch(configuration)
            Issue.record("expected a transport error")
        } catch {
            guard case .transport = error else {
                Issue.record("expected a transport error, got \(error)")
                return
            }
        }
    }

    @Test(arguments: [
        ("2026-11-24 09:29:00", 1_795_512_540.0),
        ("2026-11-24 09:29:00.250", 1_795_512_540.25),
        ("2026-11-24T09:29:00Z", 1_795_512_540.0),
        ("2026-11-24T09:29:00.250Z", 1_795_512_540.25),
    ])
    func parsesKumaTimesAsUTC(text: String, expected: TimeInterval) {
        let parsed = StatusPageAPI.parseTime(text)?.timeIntervalSince1970
        #expect(abs((parsed ?? 0) - expected) < 0.001)
    }

    @Test func ignoresMissingOrBadTimes() {
        #expect(StatusPageAPI.parseTime(nil) == nil)
        #expect(StatusPageAPI.parseTime("") == nil)
        #expect(StatusPageAPI.parseTime("yesterday") == nil)
    }
}
