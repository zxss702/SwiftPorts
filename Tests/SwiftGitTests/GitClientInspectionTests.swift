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

@Suite("GitClient inspection helpers")
struct GitClientInspectionTests {

    private func makeRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Libgit2Inspection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: dir)
        try runGit(["config", "user.email", "t@e.com"], in: dir)
        try runGit(["config", "user.name", "T"], in: dir)
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

    @Test("isIgnored honours .gitignore")
    func isIgnored() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("*.log\n".utf8).write(to: dir.appendingPathComponent(".gitignore"))
        try Data("ok\n".utf8).write(to: dir.appendingPathComponent("a.log"))
        try Data("ok\n".utf8).write(to: dir.appendingPathComponent("b.txt"))

        let client = GitClient(workingDirectory: dir)
        #expect(try client.isIgnored("a.log") == true)
        #expect(try client.isIgnored("b.txt") == false)
    }

    @Test("localBranches lists branches in alphabetical order")
    func localBranchesList() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("hi\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try runGit(["add", "a.txt"], in: dir)
        try runGit(["commit", "-m", "init"], in: dir)
        try runGit(["branch", "feature"], in: dir)
        try runGit(["branch", "alpha"], in: dir)

        let client = GitClient(workingDirectory: dir)
        let names = try client.localBranches().sorted()
        #expect(names == ["alpha", "feature", "main"])
    }

    @Test("remoteExists tracks add/lookup")
    func remoteExistsTracksAdd() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let client = GitClient(workingDirectory: dir)
        #expect(try await client.remoteExists(named: "origin") == false)

        try await client.addRemote(
            name: "origin", url: URL(string: "https://example.com/x.git")!)
        #expect(try await client.remoteExists(named: "origin") == true)
        #expect(try await client.remoteExists(named: "upstream") == false)
    }

    @Test("commitDetailed reports stats and root flag")
    func commitDetailedRoot() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try Data("b\n".utf8).write(to: dir.appendingPathComponent("b.txt"))

        let details = try await GitClient(workingDirectory: dir).commitDetailed(
            message: "init", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: false)
        #expect(details.isRoot == true)
        #expect(details.branchName == "main")
        #expect(details.filesChanged == 2)
        #expect(details.insertions == 2)
        #expect(details.deletions == 0)
        #expect(details.addedFiles.map(\.path).sorted() == ["a.txt", "b.txt"])
        #expect(details.shortSHA.count == 7)
    }

    @Test("commitDetailed reports both insertions and deletions")
    func commitDetailedModification() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v1\n".utf8).write(to: dir.appendingPathComponent("file.txt"))
        let client = GitClient(workingDirectory: dir)
        _ = try await client.commit(
            message: "first", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: false)

        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("file.txt"))
        let details = try await client.commitDetailed(
            message: "modify", author: GitSignature(name: "T", email: "t@e.com"),
            allowEmpty: false)
        #expect(details.isRoot == false)
        #expect(details.filesChanged == 1)
        #expect(details.insertions == 1)
        #expect(details.deletions == 1)
        #expect(details.addedFiles.isEmpty)
    }
}
#endif
