import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct ConfigurationTests {
    @Test func defaultsToGithubCom() {
        let config = Configuration.fromEnvironment([:])
        #expect(config.host == "github.com")
        #expect(config.token == nil)
        #expect(config.apiRoot.absoluteString == "https://api.github.com")
        #expect(config.graphQLURL.absoluteString == "https://api.github.com/graphql")
    }

    @Test func picksUpGHToken() {
        let config = Configuration.fromEnvironment(["GH_TOKEN": "abc123"])
        #expect(config.token == "abc123")
    }

    @Test func ghTokenWinsOverGithubToken() {
        let config = Configuration.fromEnvironment([
            "GH_TOKEN": "primary",
            "GITHUB_TOKEN": "fallback",
        ])
        #expect(config.token == "primary")
    }

    @Test func fallsBackToGithubToken() {
        let config = Configuration.fromEnvironment([
            "GITHUB_TOKEN": "fallback",
        ])
        #expect(config.token == "fallback")
    }

    @Test func enterpriseHostRewritesAPIRoot() {
        let config = Configuration.fromEnvironment([
            "GH_HOST": "github.example.internal",
        ])
        #expect(config.host == "github.example.internal")
        #expect(config.apiRoot.absoluteString ==
                "https://github.example.internal/api/v3")
        #expect(config.graphQLURL.absoluteString ==
                "https://github.example.internal/api/graphql")
    }

    @Test func ignoresEmptyEnvVars() {
        let config = Configuration.fromEnvironment([
            "GH_HOST": "",
            "GH_TOKEN": "",
        ])
        #expect(config.host == "github.com")
        #expect(config.token == nil)
    }
}
