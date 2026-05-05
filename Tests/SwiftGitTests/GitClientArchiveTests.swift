// Integration tests for `archiveTree`. They build a small repo via
// the system `git` CLI for fixturing only; assertions all flow
// through `GitClient.archiveTree` so the libgit2 + libarchive
// pipeline is what's exercised.
//
// Windows has no `/usr/bin/env` and the Android matrix doesn't run
// tests at all today, so gate to macOS / Linux — the same surface
// every other SwiftGit integration test covers.
#if os(macOS) || os(Linux)
import Foundation
import Testing
import TarKit
@testable import SwiftGit

@Suite("GitClient.archiveTree")
struct GitClientArchiveTests {

    private func makeRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: dir)
        try runGit(["config", "user.email", "test@example.com"], in: dir)
        try runGit(["config", "user.name", "Test"], in: dir)
        // Build a small tree so we can verify ordering + content.
        try Data("# README\n".utf8).write(
            to: dir.appendingPathComponent("README.md"))
        let nested = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(
            at: nested, withIntermediateDirectories: true)
        try Data("body\n".utf8).write(
            to: nested.appendingPathComponent("main.swift"))
        try runGit(["add", "."], in: dir)
        try runGit(["commit", "-m", "init"], in: dir)
        return dir
    }

    @discardableResult
    private func runGit(
        _ args: [String], in dir: URL, env: [String: String] = [:]
    ) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git"] + args
        p.currentDirectoryURL = dir
        if !env.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            p.environment = merged
        }
        let out = Pipe(); let err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let e = String(decoding:
                (try? err.fileHandleForReading.readToEnd()) ?? Data(),
                as: UTF8.self)
            throw Failure("git \(args.joined(separator: " ")) failed: \(e)")
        }
        return String(decoding:
            (try? out.fileHandleForReading.readToEnd()) ?? Data(),
            as: UTF8.self)
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        init(_ m: String) { self.message = m }
        var description: String { message }
    }

    @Test("plain tar round-trips through TarKit")
    func plainTar() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = SwiftGit.GitClient(workingDirectory: dir)
        let archive = dir.appendingPathComponent("snap.tar")
        try await client.archiveTree(
            treeish: "HEAD", format: .tar, to: archive)

        let extractDir = dir.appendingPathComponent("out", isDirectory: true)
        try TarKit.Archive.extract(
            from: archive,
            options: TarKit.ExtractOptions(destination: extractDir))

        #expect(FileManager.default.fileExists(
            atPath: extractDir.appendingPathComponent("README.md").path))
        let nested = try String(
            contentsOf: extractDir.appendingPathComponent("src/main.swift"),
            encoding: .utf8)
        #expect(nested == "body\n")
    }

    @Test("tar.gz format produces a valid gzip stream")
    func tarGzip() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = SwiftGit.GitClient(workingDirectory: dir)
        let archive = dir.appendingPathComponent("snap.tar.gz")
        try await client.archiveTree(
            treeish: "HEAD", format: .tarGzip, to: archive)
        let head = try FileHandle(forReadingFrom: archive).readData(ofLength: 2)
        #expect(head == Data([0x1f, 0x8b]))
    }

    @Test("tar.zst format produces a valid zstd frame")
    func tarZstd() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = SwiftGit.GitClient(workingDirectory: dir)
        let archive = dir.appendingPathComponent("snap.tar.zst")
        try await client.archiveTree(
            treeish: "HEAD", format: .tarZstd, to: archive)
        let head = try FileHandle(forReadingFrom: archive).readData(ofLength: 4)
        #expect(head == Data([0x28, 0xB5, 0x2F, 0xFD]))
    }

    @Test("zip format extracts via ZipKit")
    func zipFormat() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = SwiftGit.GitClient(workingDirectory: dir)
        let archive = dir.appendingPathComponent("snap.zip")
        try await client.archiveTree(
            treeish: "HEAD", format: .zip, to: archive)
        // PKZIP local-file-header magic: PK\x03\x04
        let head = try FileHandle(forReadingFrom: archive).readData(ofLength: 4)
        #expect(head == Data([0x50, 0x4B, 0x03, 0x04]))
    }

    @Test("entry mtimes track the commit timestamp, not wall clock")
    func reproducibleMtime() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Force the commit's author/commit date to a known value via
        // GIT_*_DATE env vars on the most recent commit.
        let when = "2020-01-15T12:34:56+00:00"
        try runGit(["commit", "--amend", "--no-edit",
                    "--date", when], in: dir, env: [
                        "GIT_COMMITTER_DATE": when,
                        "GIT_AUTHOR_DATE": when,
                    ])

        let client = SwiftGit.GitClient(workingDirectory: dir)
        let archive = dir.appendingPathComponent("snap.tar")
        try await client.archiveTree(
            treeish: "HEAD", format: .tar, to: archive)

        let entries = try TarKit.Archive.list(at: archive)
        let expected = ISO8601DateFormatter().date(from: when)!
        // Allow ±2s tolerance for tar's per-second granularity.
        for e in entries {
            guard let m = e.modificationDate else {
                Issue.record("entry \(e.path) has no modificationDate")
                continue
            }
            let delta = abs(m.timeIntervalSince(expected))
            #expect(delta < 2,
                "entry \(e.path) mtime \(m) differs from commit \(expected) by \(delta)s")
        }
    }

    @Test("--prefix prepends every entry path")
    func prefix() async throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = SwiftGit.GitClient(workingDirectory: dir)
        let archive = dir.appendingPathComponent("snap.tar")
        try await client.archiveTree(
            treeish: "HEAD", format: .tar, to: archive,
            prefix: "myproj-1.0")
        let entries = try TarKit.Archive.list(at: archive)
        #expect(entries.allSatisfy { $0.path.hasPrefix("myproj-1.0/") })
        #expect(entries.contains { $0.path == "myproj-1.0/README.md" })
    }
}
#endif
