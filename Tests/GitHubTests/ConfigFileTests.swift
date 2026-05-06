import Foundation
import Sandbox
import Testing
@testable import GitHub

@Suite struct ConfigFileTests {
    private func tempPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgh-config-\(UUID().uuidString).yml")
    }

    @Test func roundTripsScalarKeys() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = ConfigFileStore(path: path)

        var file = ConfigFile()
        file["git_protocol"] = "https"
        file["editor"] = "vim"
        file["pager"] = "less"
        try store.write(file)

        let loaded = try store.read()
        #expect(loaded["git_protocol"] == "https")
        #expect(loaded["editor"] == "vim")
        #expect(loaded["pager"] == "less")
    }

    @Test func emptyOnFirstRead() throws {
        let store = ConfigFileStore(path: tempPath())
        let file = try store.read()
        #expect(file.values.isEmpty)
    }

    @Test func interopWithUpstreamGhConfigShape() throws {
        // Mirror upstream gh's actual config.yml shape — top-level
        // scalar keys.
        let path = tempPath()
        defer { try? FileManager.default.removeItem(at: path) }
        try """
            git_protocol: ssh
            editor: code
            prompt: enabled
            """.write(to: path, atomically: true, encoding: .utf8)

        let store = ConfigFileStore(path: path)
        let file = try store.read()
        #expect(file["git_protocol"] == "ssh")
        #expect(file["editor"] == "code")
        #expect(file["prompt"] == "enabled")
    }
}

@Suite struct HostsFileTests {
    private func tempPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgh-hosts-\(UUID().uuidString).yml")
    }

    @Test func decodesUpstreamShape() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(at: path) }
        try """
            github.com:
                user: octocat
                git_protocol: https
                oauth_token: ghp_xxx
            ghe.example.com:
                user: alice
                git_protocol: ssh
            """.write(to: path, atomically: true, encoding: .utf8)

        let store = HostsFileStore(path: path)
        let file = try store.read()
        #expect(file["github.com"]?.user == "octocat")
        #expect(file["github.com"]?.gitProtocol == "https")
        #expect(file["github.com"]?.oauthToken == "ghp_xxx")
        #expect(file["ghe.example.com"]?.user == "alice")
        #expect(file["ghe.example.com"]?.oauthToken == nil)
    }

    @Test func writeAndReadBack() throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(at: path) }
        let store = HostsFileStore(path: path)

        var file = HostsFile()
        file["github.com"] = HostEntry(
            user: "test", gitProtocol: "https", oauthToken: nil)
        try store.write(file)

        let loaded = try store.read()
        #expect(loaded["github.com"]?.user == "test")
        #expect(loaded["github.com"]?.gitProtocol == "https")
    }

    @Test func emptyOnMissingFile() throws {
        let store = HostsFileStore(path: tempPath())
        let file = try store.read()
        #expect(file.hosts.isEmpty)
    }

    @Test func tokenSourceDetectsHostsFile() {
        let source = TokenSource.detect(
            env: [:], configToken: "from-hosts-file", hostsToken: "from-hosts-file")
        #expect(source == .hostsFile)
    }

    @Test func tokenSourceStillDetectsKeychainWhenHostsTokenMissing() {
        let source = TokenSource.detect(
            env: [:], configToken: "from-keychain", hostsToken: nil)
        #expect(source == .secretStore)
    }

    // MARK: - defaultPath resolution
    //
    // Regressions for chatgpt-codex-connector PR #17 review comment.
    // Mirror upstream gh's resolution order: $XDG_CONFIG_HOME wins;
    // otherwise $HOME/.config; otherwise the platform home. The
    // $HOME fallback matters for CI / wrapper scripts that set
    // HOME=/tmp/... to keep gh credentials out of the real user home.

    @Test func defaultPathHonorsXDGConfigHomeFromSandbox() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xdg-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let sandbox = Sandbox.rooted(
            at: temp,
            environment: { ["XDG_CONFIG_HOME": "/custom/xdg"] })
        await Sandbox.$current.withValue(sandbox) {
            #expect(ConfigFileStore.defaultPath.path
                    == "/custom/xdg/gh/config.yml")
            #expect(HostsFileStore.defaultPath.path
                    == "/custom/xdg/gh/hosts.yml")
        }
    }

    @Test func defaultPathHonorsHomeOverrideWhenXDGUnset() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let sandbox = Sandbox.rooted(
            at: temp,
            environment: { ["HOME": "/custom/home"] })
        await Sandbox.$current.withValue(sandbox) {
            #expect(ConfigFileStore.defaultPath.path
                    == "/custom/home/.config/gh/config.yml")
            #expect(HostsFileStore.defaultPath.path
                    == "/custom/home/.config/gh/hosts.yml")
        }
    }

    @Test func defaultPathPrefersXDGOverHome() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("both-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let sandbox = Sandbox.rooted(
            at: temp,
            environment: { ["XDG_CONFIG_HOME": "/x", "HOME": "/h"] })
        await Sandbox.$current.withValue(sandbox) {
            // XDG wins; HOME is ignored when XDG is set.
            #expect(ConfigFileStore.defaultPath.path == "/x/gh/config.yml")
            #expect(HostsFileStore.defaultPath.path == "/x/gh/hosts.yml")
        }
    }

    @Test func defaultPathFallsBackToPlatformHomeWhenBothUnset() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("none-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        // Empty env — neither XDG nor HOME supplied.
        let sandbox = Sandbox.rooted(at: temp, environment: { [:] })
        await Sandbox.$current.withValue(sandbox) {
            // Falls through to Sandbox.homeDirectory (the rooted
            // sandbox places it at <root>/home).
            #expect(ConfigFileStore.defaultPath.path
                    == sandbox.homeDirectory.appendingPathComponent(
                        ".config/gh/config.yml").path)
            #expect(HostsFileStore.defaultPath.path
                    == sandbox.homeDirectory.appendingPathComponent(
                        ".config/gh/hosts.yml").path)
        }
    }

    /// Without an active sandbox, the host process's `$HOME` env var
    /// must still be honored (preserves CI / wrapper-script use of
    /// `HOME=/tmp/... gh ...` to keep credentials out of the user
    /// home). When `$HOME` isn't set on the host either, the
    /// platform default applies.
    @Test func defaultPathHonorsHostHOMEWhenNoSandbox() {
        guard Sandbox.current == nil else {
            Issue.record("test requires no sandbox set"); return
        }
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty,
           ProcessInfo.processInfo.environment["XDG_CONFIG_HOME", default: ""].isEmpty {
            // Host has HOME set, no XDG override → defaultPath should
            // be under host HOME.
            let expected = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".config/gh/config.yml").path
            #expect(ConfigFileStore.defaultPath.path == expected)
            let expectedHosts = URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(".config/gh/hosts.yml").path
            #expect(HostsFileStore.defaultPath.path == expectedHosts)
        }
    }
}
