import Foundation

/// Static config for an API session: which host, which token, which UA.
///
/// Built from environment variables by default, but constructible
/// directly for tests or embedded use.
public struct Configuration: Sendable {
    public var host: String
    public var token: String?
    public var userAgent: String

    public init(
        host: String = Configuration.defaultHost,
        token: String? = nil,
        userAgent: String = Configuration.defaultUserAgent
    ) {
        self.host = host
        self.token = token
        self.userAgent = userAgent
    }

    public static let defaultHost = "github.com"
    public static let defaultUserAgent = "SwiftGH/0.1 (+https://github.com/cocoanetics/SwiftGH)"

    /// Build from `GH_HOST`, `GH_TOKEN`, `GITHUB_TOKEN` env vars.
    public static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Configuration {
        let host = env["GH_HOST"]?.nilIfEmpty ?? defaultHost
        let token = env["GH_TOKEN"]?.nilIfEmpty
            ?? env["GITHUB_TOKEN"]?.nilIfEmpty
        return Configuration(host: host, token: token)
    }

    /// Resolve the API root for the configured host.
    ///
    /// `github.com` → `https://api.github.com`
    /// `enterprise.example.com` → `https://enterprise.example.com/api/v3`
    public var apiRoot: URL {
        if host == "github.com" || host == "api.github.com" {
            return URL(string: "https://api.github.com")!
        }
        return URL(string: "https://\(host)/api/v3")!
    }

    public var graphQLURL: URL {
        if host == "github.com" || host == "api.github.com" {
            return URL(string: "https://api.github.com/graphql")!
        }
        return URL(string: "https://\(host)/api/graphql")!
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
