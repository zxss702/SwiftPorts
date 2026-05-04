// Integration tests that fork the system `git` via `Process` for parity
// checks. Windows has no `/usr/bin/env`, and the swift-android-action's
// MSVC clang doesn't see a stable `git.exe` path either, so gate the
// whole suite to non-Windows. Apple/Linux still cover the integration
// surface; Windows-side logic is covered by the unit-shape tests in
// `GitCommandTests` and `GitLabTests`.
#if os(macOS) || os(Linux)
import Foundation
import Testing
import ForgeKit
@testable import SwiftGit

@Suite("GitClient.commit")
struct GitClientCommitTests {

    /// Build a tmp repo using the `git` CLI for setup. The CLI is *only*
    /// for fixture creation; everything we assert against goes through
    /// `GitClient` so the test exercises libgit2 end-to-end.
    private func makeRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitClientCommitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: dir)
        try runGit(["config", "user.email", "test@example.com"], in: dir)
        try runGit(["config", "user.name", "Test"], in: dir)
        return dir
    }

    @discardableResult
    private func runGit(_ args: [String], in dir: URL) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        p.currentDirectoryURL = dir
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        p.waitUntilExit()
        let outStr = String(decoding: (try? out.fileHandleForReading.readToEnd()) ?? Data(),
                            as: UTF8.self)
        if p.terminationStatus != 0 {
            let errStr = String(decoding: (try? err.fileHandleForReading.readToEnd()) ?? Data(),
                                as: UTF8.self)
            throw Failure("git \(args.joined(separator: " ")) failed: \(errStr)")
        }
        return outStr
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        init(_ m: String) { self.message = m }
        var description: String { message }
    }

    @Test("first commit on unborn HEAD")
    func firstCommit() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("hello\n".utf8).write(to: dir.appendingPathComponent("README.md"))

        let client = GitClient(workingDirectory: dir)
        let sha = try await client.commit(
            message: "init",
            author: GitSignature(name: "Test", email: "t@example.com"),
            allowEmpty: false)

        #expect(sha.count == 40)

        // HEAD should now point at the same SHA we returned.
        let headSHA = try runGit(["rev-parse", "HEAD"], in: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(headSHA == sha)

        let branch = try await client.currentBranch()
        #expect(branch == "main")
    }

    @Test("second commit on top of first")
    func secondCommit() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("v1\n".utf8).write(to: dir.appendingPathComponent("file.txt"))
        let client = GitClient(workingDirectory: dir)
        let firstSHA = try await client.commit(
            message: "first", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: false)

        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("file.txt"))
        let secondSHA = try await client.commit(
            message: "second", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: false)

        #expect(firstSHA != secondSHA)

        // Verify the parent linkage via the CLI.
        let parent = try runGit(["rev-parse", "\(secondSHA)^"], in: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(parent == firstSHA)
    }

    @Test("empty commit refused without --allow-empty")
    func emptyCommitRefused() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("hi\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        let client = GitClient(workingDirectory: dir)
        _ = try await client.commit(
            message: "init", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: false)

        await #expect(throws: (any Error).self) {
            _ = try await client.commit(
                message: "empty", author: GitSignature(name: "T", email: "t@e.com"),
                allowEmpty: false)
        }
    }

    @Test("empty commit allowed with --allow-empty")
    func emptyCommitAllowed() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("hi\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        let client = GitClient(workingDirectory: dir)
        let firstSHA = try await client.commit(
            message: "init", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: false)
        let emptySHA = try await client.commit(
            message: "empty", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: true)

        #expect(emptySHA != firstSHA)
        let parent = try runGit(["rev-parse", "\(emptySHA)^"], in: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(parent == firstSHA)
    }

    @Test("commits with nil author use repo config")
    func defaultSignatureFromConfig() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x\n".utf8).write(to: dir.appendingPathComponent("x.txt"))

        let client = GitClient(workingDirectory: dir)
        let sha = try await client.commit(message: "no-author", author: nil, allowEmpty: false)

        let authorEmail = try runGit(["log", "-1", "--format=%ae", sha], in: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(authorEmail == "test@example.com")
    }
}
#endif
