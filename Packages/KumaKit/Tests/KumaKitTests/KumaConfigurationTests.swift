import Foundation
import Testing

@testable import KumaKit

@Suite struct KumaConfigurationTests {
    @Test func buildsTheThreeURLs() throws {
        let configuration = try KumaConfiguration.parse(address: "https://status.example.com", slug: "Home")
        #expect(configuration.slug == "home")
        #expect(configuration.pageAPIURL.absoluteString == "https://status.example.com/api/status-page/home")
        #expect(
            configuration.heartbeatAPIURL.absoluteString == "https://status.example.com/api/status-page/heartbeat/home")
        #expect(configuration.statusPageURL.absoluteString == "https://status.example.com/status/home")
    }

    @Test func takesTheSlugFromAPastedStatusPageLink() throws {
        let configuration = try KumaConfiguration.parse(address: " http://kuma.lan:3001/status/lab?x=1#top ", slug: "")
        #expect(configuration.baseURL.absoluteString == "http://kuma.lan:3001")
        #expect(configuration.slug == "lab")
    }

    @Test func keepsAReverseProxyPathPrefix() throws {
        let configuration = try KumaConfiguration.parse(address: "https://example.com/kuma/", slug: "lab")
        #expect(configuration.pageAPIURL.absoluteString == "https://example.com/kuma/api/status-page/lab")
    }

    @Test func anExplicitSlugWinsOverTheLink() throws {
        let configuration = try KumaConfiguration.parse(address: "https://example.com/status/lab", slug: "prod")
        #expect(configuration.slug == "prod")
        #expect(configuration.baseURL.absoluteString == "https://example.com")
    }

    @Test func defaultsTheSchemeAndSlug() throws {
        let configuration = try KumaConfiguration.parse(address: "status.example.com", slug: "")
        #expect(configuration.baseURL.absoluteString == "https://status.example.com")
        #expect(configuration.slug == "default")
    }

    @Test func rejectsBadInput() {
        #expect(throws: KumaConfiguration.ValidationError.invalidURL) {
            try KumaConfiguration.parse(address: "", slug: "a")
        }
        #expect(throws: KumaConfiguration.ValidationError.unsupportedScheme) {
            try KumaConfiguration.parse(address: "ftp://example.com", slug: "a")
        }
        #expect(throws: KumaConfiguration.ValidationError.invalidSlug) {
            try KumaConfiguration.parse(address: "example.com", slug: "../admin")
        }
    }

    @Test func enforcesTheMinimumInterval() {
        let configuration = KumaConfiguration(baseURL: URL(string: "https://e.com")!, slug: "a", pollInterval: 5)
        #expect(configuration.pollInterval == KumaConfiguration.minimumPollInterval)
    }

    @Test(arguments: [
        ("http://kuma.lan:3001", "http://kuma.lan:3001/api/status-page/lab", "http://kuma.lan:3001/status/lab"),
        ("kuma.lan:3001", "https://kuma.lan:3001/api/status-page/lab", "https://kuma.lan:3001/status/lab"),
        (
            "192.168.20.5:3001/status/lab", "https://192.168.20.5:3001/api/status-page/lab",
            "https://192.168.20.5:3001/status/lab"
        ),
        ("http://[fd00::5]:3001", "http://[fd00::5]:3001/api/status-page/lab", "http://[fd00::5]:3001/status/lab"),
        (
            "https://example.com:8443/kuma/", "https://example.com:8443/kuma/api/status-page/lab",
            "https://example.com:8443/kuma/status/lab"
        ),
    ])
    func keepsThePortEverywhere(address: String, pageAPI: String, statusPage: String) throws {
        let configuration = try KumaConfiguration.parse(address: address, slug: "lab")
        #expect(configuration.pageAPIURL.absoluteString == pageAPI)
        #expect(
            configuration.heartbeatAPIURL.absoluteString.hasPrefix(pageAPI.replacingOccurrences(of: "/lab", with: "")))
        #expect(configuration.statusPageURL.absoluteString == statusPage)
    }

    @Test(arguments: ["kuma.lan:0", "kuma.lan:65536", "http://kuma.lan:99999/status/lab", "kuma.lan:30o1"])
    func rejectsBadPorts(address: String) {
        #expect(throws: KumaConfiguration.ValidationError.invalidPort) {
            try KumaConfiguration.parse(address: address, slug: "lab")
        }
    }

    @Test func verifiesCertificatesUnlessToldNot() throws {
        #expect(try KumaConfiguration.parse(address: "kuma.lan", slug: "a").verifyCertificate)
        let insecure = try KumaConfiguration.parse(address: "kuma.lan:3001", slug: "a", verifyCertificate: false)
        #expect(!insecure.verifyCertificate)
        #expect(insecure.host == "kuma.lan")
    }

    @Test func settingsSavedBeforeTheCertificateOptionStillLoad() throws {
        let old = Data(#"{"baseURL":"https://kuma.lan:3001","slug":"lab","pollInterval":60}"#.utf8)
        let configuration = try JSONDecoder().decode(KumaConfiguration.self, from: old)
        #expect(configuration.verifyCertificate)
        #expect(configuration.baseURL.port == 3001)

        let roundTrip = try JSONDecoder().decode(
            KumaConfiguration.self,
            from: JSONEncoder().encode(
                KumaConfiguration(baseURL: configuration.baseURL, slug: "lab", verifyCertificate: false)))
        #expect(!roundTrip.verifyCertificate)
    }
}
