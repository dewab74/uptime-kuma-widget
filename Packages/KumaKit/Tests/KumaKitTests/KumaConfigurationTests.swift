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
}
