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

@Suite("GitClient.stash")
struct GitClientStashTests {

    private func makeRepoWithCommit() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StashTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: dir)
        try runGit(["config", "user.email", "t@e.com"], in: dir)
        try runGit(["config", "user.name", "T"], in: dir)
        try Data("v1\n".utf8).write(to: dir.appendingPathComponent("file.txt"))
        try runGit(["add", "file.txt"], in: dir)
        try runGit(["commit", "-m", "init"], in: dir)
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

    @Test("save then list captures the entry with index 0")
    func saveAndList() async throws {
        let dir = try makeRepoWithCommit()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("file.txt"))

        let client = GitClient(workingDirectory: dir)
        let sha = try await client.stashSave(
            message: "wip", author: GitSignature(name: "T", email: "t@e.com"))
        #expect(sha.count == 40)

        let entries = try await client.stashList()
        #expect(entries.count == 1)
        #expect(entries.first?.index == 0)
        #expect(entries.first?.message.contains("wip") == true)
    }

    @Test("apply restores the working tree change")
    func applyRestoresWorkingTree() async throws {
        let dir = try makeRepoWithCommit()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("file.txt"))

        let client = GitClient(workingDirectory: dir)
        try await client.stashSave(message: nil, author: GitSignature(name: "T", email: "t@e.com"))

        // Confirm working tree was reverted by libgit2.
        let restored1 = try Data(contentsOf: dir.appendingPathComponent("file.txt"))
        #expect(String(decoding:restored1, as: UTF8.self) == "v1\n")

        try await client.stashApply(index: 0)
        let restored2 = try Data(contentsOf: dir.appendingPathComponent("file.txt"))
        #expect(String(decoding:restored2, as: UTF8.self) == "v2\n")

        // Apply does NOT drop — entry should still be there.
        let entries = try await client.stashList()
        #expect(entries.count == 1)
    }

    @Test("pop applies and removes the entry")
    func popAppliesAndRemoves() async throws {
        let dir = try makeRepoWithCommit()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("file.txt"))

        let client = GitClient(workingDirectory: dir)
        try await client.stashSave(message: "x", author: GitSignature(name: "T", email: "t@e.com"))
        try await client.stashPop(index: 0)

        let entries = try await client.stashList()
        #expect(entries.isEmpty)
        let restored = try Data(contentsOf: dir.appendingPathComponent("file.txt"))
        #expect(String(decoding:restored, as: UTF8.self) == "v2\n")
    }

    @Test("drop removes one entry without applying it")
    func dropRemoves() async throws {
        let dir = try makeRepoWithCommit()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("file.txt"))

        let client = GitClient(workingDirectory: dir)
        try await client.stashSave(message: "x", author: GitSignature(name: "T", email: "t@e.com"))
        try await client.stashDrop(index: 0)

        let entries = try await client.stashList()
        #expect(entries.isEmpty)
        // Working tree should remain at v1 — drop does NOT apply.
        let after = try Data(contentsOf: dir.appendingPathComponent("file.txt"))
        #expect(String(decoding:after, as: UTF8.self) == "v1\n")
    }

    @Test("clear removes every entry, newest-to-oldest")
    func clearRemovesAll() async throws {
        let dir = try makeRepoWithCommit()
        defer { try? FileManager.default.removeItem(at: dir) }

        let client = GitClient(workingDirectory: dir)
        for i in 1...3 {
            // Each iteration must produce a new diff against HEAD.
            // After the previous save, the working tree was reverted to
            // v1, so we offset the content with the iteration index.
            try Data("change \(i)\n".utf8).write(to: dir.appendingPathComponent("file.txt"))
            try await client.stashSave(
                message: "stash \(i)", author: GitSignature(name: "T", email: "t@e.com"))
        }
        #expect(try await client.stashList().count == 3)
        try await client.stashClear()
        #expect(try await client.stashList().isEmpty)
    }

    @Test("show returns diff stats against the parent commit")
    func showReportsStats() async throws {
        let dir = try makeRepoWithCommit()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\nadded\n".utf8).write(to: dir.appendingPathComponent("file.txt"))

        let client = GitClient(workingDirectory: dir)
        try await client.stashSave(message: nil, author: GitSignature(name: "T", email: "t@e.com"))

        let stats = try await client.stashShow(index: 0)
        #expect(stats.filesChanged == 1)
        #expect(stats.insertions >= 1)
    }

    @Test("branch creates a new branch and applies the stash there")
    func branchAppliesOnNewBranch() async throws {
        let dir = try makeRepoWithCommit()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("file.txt"))

        let client = GitClient(workingDirectory: dir)
        try await client.stashSave(message: nil, author: GitSignature(name: "T", email: "t@e.com"))
        try await client.stashBranch(name: "wip-branch", index: 0)

        let current = try await client.currentBranch()
        #expect(current == "wip-branch")
        let after = try Data(contentsOf: dir.appendingPathComponent("file.txt"))
        #expect(String(decoding:after, as: UTF8.self) == "v2\n")
        // Applied + dropped — list should be empty.
        let entries = try await client.stashList()
        #expect(entries.isEmpty)
    }
}
#endif
