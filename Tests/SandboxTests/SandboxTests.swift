import Foundation
import Testing
@testable import Sandbox

// MARK: - Default-permissive (no current sandbox)

@Suite struct DefaultBehaviorTests {

    @Test func authorizeIsNoOpWhenNoCurrentSandbox() async throws {
        // No Sandbox.current — every URL is permitted.
        try await Sandbox.authorize(URL(fileURLWithPath: "/etc/passwd"))
        try await Sandbox.authorize(URL(string: "https://example.com")!)
        try await Sandbox.authorize(URL(fileURLWithPath: "/usr/bin/git"))
    }

    @Test func staticEnvFallsBackToProcessInfoWhenNoSandbox() {
        // Static accessor should pass through to ProcessInfo when
        // current is nil — preserves existing behavior.
        let path = Sandbox.env("PATH") ?? Sandbox.env("Path") ?? ""
        // We can't assert on a specific value of $PATH on every CI
        // host, but we can confirm the accessor returns whatever
        // ProcessInfo would.
        #expect(path == ProcessInfo.processInfo.environment["PATH"]
                ?? ProcessInfo.processInfo.environment["Path"]
                ?? "")
    }

    @Test func staticArgumentsFallsBackToProcessInfoWhenNoSandbox() {
        let args = Sandbox.arguments
        #expect(args == ProcessInfo.processInfo.arguments)
    }

    @Test func staticCurrentDirectoryFallsBackToProcessCWDWhenNoSandbox() {
        let dir = Sandbox.currentDirectory
        let processCWD = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true)
        #expect(dir.path == processCWD.path)
    }

    @Test func staticHomeDirectoryFallsBackWhenNoSandbox() {
        let home = Sandbox.homeDirectory
        // Just confirm the call returns a non-empty URL — exact value
        // depends on platform.
        #expect(!home.path.isEmpty)
    }

    /// Regression for chatgpt-codex-connector PR #17 review comment.
    ///
    /// Without an active sandbox, `currentDirectory` MUST report the
    /// OS CWD (`getcwd(3)` via `FileManager.default.currentDirectoryPath`),
    /// **not** the host process's `$PWD` env var. `$PWD` is a shell
    /// convention; an embedder calling `chdir(2)` /
    /// `FileManager.changeCurrentDirectoryPath(_:)` without rewriting
    /// `$PWD` will leave it stale, and downstream relative-path
    /// resolution must not target the wrong directory.
    @Test func staticCurrentDirectoryIgnoresHostPWDWhenNoSandbox() {
        // Even if the host has PWD set (it usually does), our static
        // accessor must report the OS CWD — which equals
        // FileManager.default.currentDirectoryPath, not env["PWD"].
        // (We can't unset PWD on the host process from a test, but we
        // CAN demonstrate the accessor doesn't return that value when
        // the OS CWD differs from PWD. Use the actual OS CWD as the
        // contract: `Sandbox.currentDirectory.path` must always equal
        // `FileManager.default.currentDirectoryPath` outside a sandbox.)
        #expect(Sandbox.current == nil, "test requires no sandbox set")
        // Compare via standardized URL form so Windows path separators
        // (`\` from FileManager vs `/` from URL.path) don't trip the
        // string compare.
        let osCWD = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true).standardizedFileURL
        #expect(Sandbox.currentDirectory.standardizedFileURL == osCWD)
    }
}

// MARK: - rooted(at:)

@Suite struct RootedSandboxTests {

    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func regionsArePopulatedAsSubpathsOfRoot() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)

        // Every region is a subpath of root (or root itself for
        // userDirectory).
        let rootPath = root.standardizedFileURL.path
        let regions: [URL] = [
            sandbox.documentsDirectory,
            sandbox.downloadsDirectory,
            sandbox.libraryDirectory,
            sandbox.moviesDirectory,
            sandbox.musicDirectory,
            sandbox.picturesDirectory,
            sandbox.sharedPublicDirectory,
            sandbox.temporaryDirectory,
            sandbox.trashDirectory,
            sandbox.userDirectory,
            sandbox.cachesDirectory,
            sandbox.homeDirectory,
        ]
        for region in regions {
            let regionPath = region.standardizedFileURL.path
            let isUnderRoot = regionPath == rootPath
                || regionPath.hasPrefix(rootPath + "/")
            #expect(isUnderRoot, "\(regionPath) is not under \(rootPath)")
        }
    }

    @Test func authorizeAcceptsURLsUnderRoot() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        let inside = root.appendingPathComponent("foo.txt")
        try await sandbox.authorize(inside)
    }

    @Test func authorizeDeniesURLsOutsideRoot() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        let outside = URL(fileURLWithPath: "/etc/passwd")
        await #expect(throws: Sandbox.Denial.self) {
            try await sandbox.authorize(outside)
        }
    }

    @Test func denialPopulatesSuggestionForOutsideURL() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        let outside = URL(fileURLWithPath: "/etc/passwd")
        do {
            try await sandbox.authorize(outside)
            Issue.record("expected denial")
        } catch let denial as Sandbox.Denial {
            #expect(denial.url == outside)
            #expect(denial.suggestion != nil)
            // The suggestion should point at the equivalent path
            // under root.
            let canonicalRoot = canonicalizePath(root.path) ?? root.standardizedFileURL.path
            #expect(denial.suggestion?.path
                    == URL(fileURLWithPath: canonicalRoot)
                        .appendingPathComponent("etc/passwd").path)
        }
    }

    #if !os(Windows)
    // Windows: symlink creation requires admin/developer mode and our
    // canonicalization currently uses URL.standardizedFileURL (no
    // realpath equivalent), so symlink-escape protection is partial.
    // Tracked as a follow-up; the realpath-backed defense holds on
    // POSIX platforms which is what this test verifies.
    @Test func authorizeRejectsSymlinkInsideRootPointingOutside() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)

        // Create a symlink inside root pointing at /etc/passwd.
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))

        await #expect(throws: Sandbox.Denial.self) {
            try await sandbox.authorize(link)
        }
    }
    #endif

    @Test func authorizeAcceptsAllowlistedHost() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(
            at: root,
            allowedHosts: ["api.github.com"])

        try await sandbox.authorize(
            URL(string: "https://api.github.com/user")!)
    }

    @Test func authorizeDeniesNonAllowlistedHost() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(
            at: root,
            allowedHosts: ["api.github.com"])

        await #expect(throws: Sandbox.Denial.self) {
            try await sandbox.authorize(
                URL(string: "https://example.com")!)
        }
    }

    @Test func authorizeDeniesProcessExecutableURLOutsideRoot() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        let exec = URL(fileURLWithPath: "/usr/bin/git")
        await #expect(throws: Sandbox.Denial.self) {
            try await sandbox.authorize(exec)
        }
    }

    @Test func authorizeRejectsDotDotTraversal() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        let escape = root.appendingPathComponent("../../../etc/passwd")
        await #expect(throws: Sandbox.Denial.self) {
            try await sandbox.authorize(escape)
        }
    }

    @Test func authorizeAcceptsNonExistentWritePathUnderRoot() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // A write path under root that doesn't exist yet — common
        // case of "authorize before creating the file".
        let target = root.appendingPathComponent("newfile.txt")
        let sandbox = Sandbox.rooted(at: root)
        try await sandbox.authorize(target)
    }

    @Test func defaultEnvironmentSuppliesPWD() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        let env = sandbox.environment()
        #expect(env["PWD"] != nil)
        // PWD should be the canonical root path.
        let canonicalRoot = canonicalizePath(root.path)
            ?? root.standardizedFileURL.path
        #expect(env["PWD"] == canonicalRoot)
    }

    @Test func defaultArgumentsAreEmpty() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        #expect(sandbox.arguments() == [])
    }

    @Test func customEnvironmentClosureIsUsed() throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(
            at: root,
            environment: { ["FOO": "bar", "PATH": "/sandbox/bin"] })
        let env = sandbox.environment()
        #expect(env["FOO"] == "bar")
        #expect(env["PATH"] == "/sandbox/bin")
        // Custom closure overrides PWD default — caller is responsible.
        #expect(env["PWD"] == nil)
    }

    @Test func twoSandboxesWithDifferentRootsHaveDifferentRegions() throws {
        let rootA = try makeTempRoot()
        let rootB = try makeTempRoot()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let sandboxA = Sandbox.rooted(at: rootA)
        let sandboxB = Sandbox.rooted(at: rootB)

        #expect(sandboxA.documentsDirectory != sandboxB.documentsDirectory)
        #expect(sandboxA.cachesDirectory != sandboxB.cachesDirectory)
        #expect(sandboxA.temporaryDirectory != sandboxB.temporaryDirectory)
    }
}

// MARK: - TaskLocal propagation

@Suite struct TaskLocalPropagationTests {

    @Test func currentIsVisibleAcrossAwait() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        try await Sandbox.$current.withValue(sandbox) {
            try await Task.yield()  // force a scheduling hop
            #expect(Sandbox.current != nil)
            try await Sandbox.authorize(root.appendingPathComponent("ok"))
        }
        #expect(Sandbox.current == nil)
    }

    @Test func currentIsVisibleInsideTaskGroup() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)
        try await Sandbox.$current.withValue(sandbox) {
            try await withThrowingTaskGroup(of: Bool.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        Sandbox.current != nil
                    }
                }
                for try await visible in group {
                    #expect(visible)
                }
            }
        }
    }

    @Test func staticEnvReadsThroughCurrent() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(
            at: root,
            environment: { ["FOO": "from-sandbox"] })

        await Sandbox.$current.withValue(sandbox) {
            #expect(Sandbox.env("FOO") == "from-sandbox")
            #expect(Sandbox.environment["FOO"] == "from-sandbox")
        }

        // After unbinding, falls back to ProcessInfo (which doesn't
        // have FOO unless someone set it externally).
        #expect(Sandbox.env("FOO") == ProcessInfo.processInfo.environment["FOO"])
    }

    @Test func staticCurrentDirectoryReadsPWDFromSandbox() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let canonicalRoot = canonicalizePath(root.path)
            ?? root.standardizedFileURL.path

        let sandbox = Sandbox.rooted(at: root)
        await Sandbox.$current.withValue(sandbox) {
            #expect(Sandbox.currentDirectory.path == canonicalRoot)
        }
    }

    @Test func staticArgumentsReadsFromSandbox() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(
            at: root,
            arguments: { ["myprog", "--flag", "value"] })

        await Sandbox.$current.withValue(sandbox) {
            #expect(Sandbox.arguments == ["myprog", "--flag", "value"])
        }
    }

    @Test func defaultEnvironmentDoesNotLeakHostEnv() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(at: root)  // default env is { ["PWD": ...] }
        await Sandbox.$current.withValue(sandbox) {
            // Common host env keys should not be visible — we're
            // default-deny.
            #expect(Sandbox.env("PATH") == nil)
            #expect(Sandbox.env("HOME") == nil)
            // Only PWD is supplied by the default rooted environment.
            #expect(Sandbox.env("PWD") != nil)
        }
    }

    @Test func explicitPassthroughEnvironmentRestoresHostEnv() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let sandbox = Sandbox.rooted(
            at: root,
            environment: { ProcessInfo.processInfo.environment })
        await Sandbox.$current.withValue(sandbox) {
            // Embedder explicitly chose passthrough — host env visible.
            #expect(Sandbox.env("PATH") == ProcessInfo.processInfo.environment["PATH"])
        }
    }
}

// MARK: - Denial.suggestion contract

@Suite struct DenialSuggestionContractTests {

    /// Encodes the contract that a caller MUST NOT blind-retry with
    /// `denial.suggestion` and expect success. The default rooted
    /// gatekeeper happens to accept the suggestion (because it
    /// constructs it as a path under root), but the contract permits
    /// a custom gatekeeper to deny it again. This test demonstrates
    /// the contract by constructing a custom gatekeeper that rejects
    /// the suggestion.
    @Test func suggestionIsHintNotGuarantee() async throws {
        let alwaysDeny = Sandbox(
            documentsDirectory: URL(fileURLWithPath: "/sandbox/Documents"),
            downloadsDirectory: URL(fileURLWithPath: "/sandbox/Downloads"),
            libraryDirectory: URL(fileURLWithPath: "/sandbox/Library"),
            moviesDirectory: URL(fileURLWithPath: "/sandbox/Movies"),
            musicDirectory: URL(fileURLWithPath: "/sandbox/Music"),
            picturesDirectory: URL(fileURLWithPath: "/sandbox/Pictures"),
            sharedPublicDirectory: URL(fileURLWithPath: "/sandbox/Public"),
            temporaryDirectory: URL(fileURLWithPath: "/sandbox/tmp"),
            trashDirectory: URL(fileURLWithPath: "/sandbox/.Trash"),
            userDirectory: URL(fileURLWithPath: "/sandbox"),
            cachesDirectory: URL(fileURLWithPath: "/sandbox/Library/Caches"),
            authorize: { url in
                throw Sandbox.Denial(
                    url: url,
                    reason: "this gatekeeper denies everything",
                    suggestion: URL(fileURLWithPath: "/sandbox/imaginary"))
            })

        let original = URL(fileURLWithPath: "/etc/passwd")
        do {
            try await alwaysDeny.authorize(original)
            Issue.record("expected denial")
        } catch let denial as Sandbox.Denial {
            #expect(denial.suggestion != nil)
            // Blind retry — also denied, by contract.
            await #expect(throws: Sandbox.Denial.self) {
                try await alwaysDeny.authorize(denial.suggestion!)
            }
        }
    }
}

// MARK: - appContainer(id:)

@Suite struct AppContainerSandboxTests {

    @Test func instanceIdNamespacesWritableRegions() throws {
        let plain = Sandbox.appContainer()
        let scoped = Sandbox.appContainer(id: "abc")

        // Documents / Caches / tmp differ between scoped and plain.
        #expect(plain.documentsDirectory != scoped.documentsDirectory)
        #expect(plain.cachesDirectory != scoped.cachesDirectory)
        #expect(plain.temporaryDirectory != scoped.temporaryDirectory)

        // Scoped paths contain the id component.
        #expect(scoped.documentsDirectory.path.contains("sandbox-abc"))
        #expect(scoped.cachesDirectory.path.contains("sandbox-abc"))
        #expect(scoped.temporaryDirectory.path.contains("sandbox-abc"))
    }

    @Test func twoIdsHaveNonOverlappingRegions() {
        let a = Sandbox.appContainer(id: "a")
        let b = Sandbox.appContainer(id: "b")

        #expect(a.documentsDirectory != b.documentsDirectory)
        #expect(a.cachesDirectory != b.cachesDirectory)
        #expect(a.temporaryDirectory != b.temporaryDirectory)
    }
}

// MARK: - Helpers

private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sandbox-test-\(UUID().uuidString)",
                                isDirectory: true)
    try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true)
    return url
}
