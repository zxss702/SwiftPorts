import Foundation
import Testing
@testable import GitHub
import ForgeKit

@Suite struct ConfigurationResolverTests {
    @Test func detectsGHTokenEnvSource() {
        let source = TokenSource.detect(
            env: ["GH_TOKEN": "abc"], configToken: "abc")
        #expect(source == .ghTokenEnv)
    }

    @Test func detectsGitHubTokenEnvSource() {
        let source = TokenSource.detect(
            env: ["GITHUB_TOKEN": "fallback"], configToken: "fallback")
        #expect(source == .githubTokenEnv)
    }

    @Test func detectsSecretStoreSource() {
        // Env empty but config has a token → must have come from store.
        let source = TokenSource.detect(env: [:], configToken: "from-keychain")
        #expect(source == .secretStore)
    }

    @Test func detectsNoneSource() {
        let source = TokenSource.detect(env: [:], configToken: nil)
        #expect(source == .none)
    }

    @Test func resolverReadsFromSecretStoreWhenEnvEmpty() async throws {
        let store = InMemorySecretStore()
        try await store.set(
            service: "com.swiftgh.gh",
            account: "github.com",
            secret: "stashed-token")
        // Note: we can't easily clear real env vars in-process, so this
        // test only verifies the secret-store path is *consulted* — the
        // actual ordering is exercised by integration tests when env is
        // empty.
        let resolver = ConfigurationResolver(secretStore: store)
        let config = try await resolver.resolve(host: "github.com")
        // If env has GH_TOKEN/GITHUB_TOKEN set in CI, they win — and
        // that's fine. Without env tokens, we get the keychain value.
        let envToken = ProcessInfo.processInfo.environment["GH_TOKEN"]
            ?? ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
        let expected = (envToken?.isEmpty == false) ? envToken! : "stashed-token"
        #expect(config.token == expected)
    }

    @Test func storeAndRemoveRoundTrip() async throws {
        let store = InMemorySecretStore()
        let resolver = ConfigurationResolver(secretStore: store)
        try await resolver.store(token: "t1", host: "github.com")
        let stored = try await store.get(
            service: ConfigurationResolver.defaultService,
            account: "github.com")
        #expect(stored == "t1")
        try await resolver.remove(host: "github.com")
        let after = try await store.get(
            service: ConfigurationResolver.defaultService,
            account: "github.com")
        #expect(after == nil)
    }

    @Test func hostFlagOverridesEnv() async throws {
        let store = InMemorySecretStore()
        let resolver = ConfigurationResolver(secretStore: store)
        let config = try await resolver.resolve(host: "ghe.example.com")
        #expect(config.host == "ghe.example.com")
        #expect(config.apiRoot.absoluteString == "https://ghe.example.com/api/v3")
    }
}
