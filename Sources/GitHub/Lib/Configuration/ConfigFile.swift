import Foundation
import Sandbox
import Yams

/// Parsed `~/.config/gh/config.yml`. Global preferences (no per-host
/// data — that lives in `HostsFile`).
///
/// Mirrors the keys upstream `gh` uses, so the two CLIs read each
/// other's config without translation. Unrecognised keys are
/// preserved across read/write so we don't clobber upstream-gh
/// settings we don't understand yet.
public struct ConfigFile: Sendable {
    public var values: [String: String]

    public init(values: [String: String] = [:]) { self.values = values }

    public subscript(key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public static let knownKeys: Set<String> = [
        "git_protocol", "editor", "prompt", "pager",
        "http_unix_socket", "browser",
    ]
}

public struct ConfigFileStore: Sendable {
    public let path: URL

    public init(path: URL = ConfigFileStore.defaultPath) {
        self.path = path
    }

    public static var defaultPath: URL {
        // Resolution order matches HostsFileStore.defaultPath:
        // $XDG_CONFIG_HOME → $HOME/.config → platform home/.config.
        // Steps 1 and 2 honor explicit env overrides; only fall
        // through to the platform home when both are unset.
        let dir: URL
        if let xdg = Sandbox.env("XDG_CONFIG_HOME"), !xdg.isEmpty {
            dir = URL(fileURLWithPath: xdg, isDirectory: true)
        } else if let home = Sandbox.env("HOME"), !home.isEmpty {
            dir = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".config", isDirectory: true)
        } else {
            // Sandbox.homeDirectory handles iOS-availability internally.
            dir = Sandbox.homeDirectory
                .appendingPathComponent(".config", isDirectory: true)
        }
        return dir
            .appendingPathComponent("gh", isDirectory: true)
            .appendingPathComponent("config.yml")
    }

    public func read() throws -> ConfigFile {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return ConfigFile()
        }
        let raw = try String(contentsOf: path, encoding: .utf8)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ConfigFile()
        }
        // Upstream gh's config.yml has scalar string values everywhere
        // — easy enough to load without a custom Codable shape. We use
        // a permissive [String: Yams.Node] decode so unknown keys
        // round-trip even if they aren't strings.
        let node = try Yams.compose(yaml: raw)
        var values: [String: String] = [:]
        if case let .mapping(mapping)? = node {
            for (keyNode, valueNode) in mapping {
                guard case let .scalar(keyScalar) = keyNode else { continue }
                if case let .scalar(valueScalar) = valueNode {
                    values[keyScalar.string] = valueScalar.string
                }
            }
        }
        return ConfigFile(values: values)
    }

    public func write(_ file: ConfigFile) throws {
        try ensureDirectoryExists()
        let yaml = try YAMLEncoder().encode(file.values)
        try yaml.write(to: path, atomically: true, encoding: .utf8)
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
