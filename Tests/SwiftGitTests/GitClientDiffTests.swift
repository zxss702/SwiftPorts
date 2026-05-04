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

@Suite("GitClient.diff")
struct GitClientDiffTests {

    private func makeRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiffTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: dir)
        try runGit(["config", "user.email", "t@e.com"], in: dir)
        try runGit(["config", "user.name", "T"], in: dir)
        try Data("line1\nline2\nline3\n".utf8)
            .write(to: dir.appendingPathComponent("a.txt"))
        try runGit(["add", "a.txt"], in: dir)
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

    @Test("workdir vs index includes unstaged change")
    func workdirVsIndex() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("line1\nLINE TWO\nline3\n".utf8)
            .write(to: dir.appendingPathComponent("a.txt"))

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex)
        #expect(out.contains("diff --git a/a.txt b/a.txt"))
        #expect(out.contains("-line2"))
        #expect(out.contains("+LINE TWO"))
    }

    @Test("workdir vs index is empty when working tree is clean")
    func workdirVsIndexClean() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex)
        #expect(out.isEmpty)
    }

    @Test("index vs HEAD shows staged changes only")
    func indexVsHead() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try runGit(["add", "a.txt"], in: dir)

        let client = GitClient(workingDirectory: dir)
        let staged = try await client.diff(.indexVsHead)
        #expect(staged.contains("diff --git a/a.txt b/a.txt"))
        let unstaged = try await client.diff(.workdirVsIndex)
        #expect(unstaged.isEmpty)
    }

    @Test("--stat format produces summary line")
    func statFormat() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("line1\nLINE TWO\nline3\nline4\n".utf8)
            .write(to: dir.appendingPathComponent("a.txt"))

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex, format: .stat)
        #expect(out.contains("a.txt"))
        #expect(out.contains("file changed"))
        #expect(out.contains("insertion"))
    }

    @Test("--name-only format prints just the path")
    func nameOnlyFormat() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("a.txt"))

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex, format: .nameOnly)
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "a.txt")
    }

    @Test("--name-status format prefixes with M")
    func nameStatusFormat() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("a.txt"))

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex, format: .nameStatus)
        #expect(out.contains("M\ta.txt"))
    }

    @Test("commit-vs-commit diff between HEAD and a previous commit")
    func commitVsCommit() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\nv3\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try runGit(["add", "a.txt"], in: dir)
        try runGit(["commit", "-m", "second"], in: dir)

        let out = try await GitClient(workingDirectory: dir)
            .diff(.commitVsCommit("HEAD~1", "HEAD"))
        #expect(out.contains("diff --git a/a.txt b/a.txt"))
        #expect(out.contains("-line1"))
        #expect(out.contains("+v2"))
    }

    @Test("contextLines = 0 produces zero-context unified diff")
    func contextLinesZero() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("line1\nLINE TWO\nline3\n".utf8)
            .write(to: dir.appendingPathComponent("a.txt"))

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex, format: .patch, contextLines: 0)
        // -U0 means no surrounding context. Hunk header declares a
        // 1-line span. Body must contain only the changed lines —
        // unchanged context lines (rendered as " <text>") absent.
        #expect(out.contains("@@ -2 +2 @@"))
        #expect(out.contains("-line2"))
        #expect(out.contains("+LINE TWO"))
        let bodyLines = out.split(separator: "\n").filter {
            $0.first == " "      // context lines are exactly " <text>"
        }
        #expect(bodyLines.isEmpty)
    }

    @Test("--shortstat produces just the summary line")
    func shortStatFormat() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("line1\nLINE TWO\nline3\nline4\n".utf8)
            .write(to: dir.appendingPathComponent("a.txt"))

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex, format: .shortStat)
        #expect(out.contains("file changed"))
        // shortstat must NOT include the per-file bar line.
        #expect(!out.contains("a.txt |"))
    }

    @Test("--numstat is tab-separated, real-git compatible")
    func numStatFormat() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("line1\nLINE TWO\nline3\nline4\n".utf8)
            .write(to: dir.appendingPathComponent("a.txt"))

        let out = try await GitClient(workingDirectory: dir)
            .diff(.workdirVsIndex, format: .numStat)
        // adds=2 dels=1 path=a.txt with TAB separators.
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "2\t1\ta.txt")
    }

    @Test("--raw matches real git format (no SHA ellipsis)")
    func rawFormat() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("v2\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try runGit(["add", "a.txt"], in: dir)

        let out = try await GitClient(workingDirectory: dir)
            .diff(.indexVsHead, format: .raw)
        // ":<oldmode> <newmode> <oldsha7> <newsha7> M\t<path>"
        let line = out.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line.hasPrefix(":100644 100644 "))
        #expect(line.hasSuffix("M\ta.txt"))
        // Must not contain libgit2's `...` ellipsis marker.
        #expect(!line.contains("..."))
    }

    @Test("mergeBase resolves to the common ancestor")
    func mergeBaseLookup() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Two commits already exist (init), need a divergent branch.
        let baseSHA = try runGit(["rev-parse", "HEAD"], in: dir)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try runGit(["checkout", "-b", "feature"], in: dir)
        try Data("feat\n".utf8).write(to: dir.appendingPathComponent("b.txt"))
        try runGit(["add", "b.txt"], in: dir)
        try runGit(["commit", "-m", "feat"], in: dir)
        try runGit(["checkout", "main"], in: dir)
        try Data("trunk\n".utf8).write(to: dir.appendingPathComponent("c.txt"))
        try runGit(["add", "c.txt"], in: dir)
        try runGit(["commit", "-m", "trunk"], in: dir)

        let mb = try await GitClient(workingDirectory: dir)
            .mergeBase("main", "feature")
        #expect(mb == baseSHA)
    }

    @Test("canResolveRef returns true for HEAD, false for non-ref")
    func canResolveRefBasic() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = GitClient(workingDirectory: dir)
        #expect(try await client.canResolveRef("HEAD") == true)
        #expect(try await client.canResolveRef("main") == true)
        #expect(try await client.canResolveRef("not-a-ref-anywhere") == false)
    }

    @Test("pathspec filter restricts the diff to one file")
    func pathspecFilter() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("a-edit\n".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try Data("new\n".utf8).write(to: dir.appendingPathComponent("b.txt"))
        try runGit(["add", "."], in: dir)

        let client = GitClient(workingDirectory: dir)
        let onlyA = try await client.diff(
            .indexVsHead, format: .nameOnly, paths: ["a.txt"])
        #expect(onlyA.trimmingCharacters(in: .whitespacesAndNewlines) == "a.txt")
    }
}
#endif
