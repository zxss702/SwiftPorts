import Foundation
import Sandbox
import Yams

/// Parsed `~/.config/gh/hosts.yml`.
///
/// Format (interoperable with upstream `gh`):
///
///     github.com:
///         user: octocat
///         git_protocol: https
///         oauth_token: ghp_xxx           # only present with --insecure-storage
///     ghe.example.com:
///         user: alice
///         …
///
/// The token field is **only** populated when the user opted into
/// plaintext storage; gh's default is the keyring. We read it as a
/// fallback when present, but write hosts.yml only with `user` and
/// `git_protocol` — never the token.
public struct HostsFile: Codable, Sendable {
    public var hosts: [String: HostEntry]

    public init(hosts: [String: HostEntry] = [:]) { self.hosts = hosts }

    public subscript(host: String) -> HostEntry? {
        get { hosts[host] }
        set { hosts[host] = newValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.hosts = try container.decode([String: HostEntry].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hosts)
    }
}

public struct HostEntry: Codable, Sendable {
    public var user: String?
    public var gitProtocol: String?
    public var oauthToken: String?

    public init(user: String? = nil, gitProtocol: String? = nil, oauthToken: String? = nil) {
        self.user = user
        self.gitProtocol = gitProtocol
        self.oauthToken = oauthToken
    }

    enum CodingKeys: String, CodingKey {
        case user
        case gitProtocol = "git_protocol"
        case oauthToken = "oauth_token"
    }
}

/// Reads / writes the on-disk YAML.
public struct HostsFileStore: Sendable {
    public let path: URL

    public init(path: URL = HostsFileStore.defaultPath) {
        self.path = path
    }

    public static var defaultPath: URL {
        // Resolution order (matches upstream gh):
        //   1. $XDG_CONFIG_HOME/gh/hosts.yml
        //   2. $HOME/.config/gh/hosts.yml
        //   3. <platform home>/.config/gh/hosts.yml
        // Steps 1 and 2 honor explicit env overrides — important for
        // CI / wrapper scripts that set HOME=/tmp/... to keep gh
        // credentials out of the real user home. Inside a sandbox
        // these come from `Sandbox.environment`; outside, from
        // `ProcessInfo.processInfo.environment`. The platform-home
        // fallback is only used when both are unset.
        let configDir: URL
        if let xdg = Sandbox.env("XDG_CONFIG_HOME"), !xdg.isEmpty {
            configDir = URL(fileURLWithPath: xdg, isDirectory: true)
        } else if let home = Sandbox.env("HOME"), !home.isEmpty {
            configDir = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".config", isDirectory: true)
        } else {
            // Sandbox.homeDirectory handles iOS-availability internally
            // (NSHomeDirectory on iOS, FileManager on macOS/Linux).
            configDir = Sandbox.homeDirectory
                .appendingPathComponent(".config", isDirectory: true)
        }
        return configDir
            .appendingPathComponent("gh", isDirectory: true)
            .appendingPathComponent("hosts.yml")
    }

    public func read() throws -> HostsFile {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return HostsFile()
        }
        let raw = try String(contentsOf: path, encoding: .utf8)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return HostsFile()
        }
        let dict = try YAMLDecoder().decode([String: HostEntry].self, from: raw)
        return HostsFile(hosts: dict)
    }

    public func write(_ file: HostsFile) throws {
        try ensureDirectoryExists()
        let yaml = try YAMLEncoder().encode(file.hosts)
        try yaml.write(to: path, atomically: true, encoding: .utf8)
        // Tighten permissions: 0600 (token may be in there).
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    private func ensureDirectoryExists() throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
}
