import Foundation
import Testing
@testable import TarKit

// Direct libarchive access so we can mint tar entries with hostile
// pathnames that TarKit's own `create()` refuses to produce.
import struct Archive.ArchiveEntry
import class Archive.ArchiveWriter
import enum Archive.ArchiveFormat
import enum Archive.ArchiveFilter
import enum Archive.FileType

@Suite struct TarKitSecurityTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tarkit-sec-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    /// Hand-builds a tar archive with one regular-file entry whose
    /// pathname is whatever the caller specifies — including hostile
    /// values our own walk()-based `create()` would never produce.
    private func writeArchive(
        at url: URL, entryPath: String, content: Data
    ) throws {
        let writer = try ArchiveWriter(
            path: url.path, format: .tar, filters: [.none])
        let entry = ArchiveEntry(
            pathname: entryPath,
            size: Int64(content.count),
            fileType: .regular,
            permissions: 0o644)
        try writer.writeEntry(entry, data: content)
        try writer.close()
    }

    @Test func extractRejectsParentTraversal() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appendingPathComponent("evil.tar")
        try writeArchive(
            at: archive,
            entryPath: "../../escape.txt",
            content: Data("pwned\n".utf8))

        let dest = work.appendingPathComponent("safe", isDirectory: true)
        await #expect(throws: TarKitError.self) {
            try await TarKit.Archive.extract(
                from: archive,
                options: TarKit.ExtractOptions(destination: dest))
        }
        // Verify nothing was written above the destination root.
        let escapeAbove = work.appendingPathComponent("escape.txt")
        #expect(!FileManager.default.fileExists(atPath: escapeAbove.path))
    }

    @Test func extractRejectsAbsolutePath() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appendingPathComponent("evil.tar")
        try writeArchive(
            at: archive,
            entryPath: "/etc/oops",
            content: Data("nope".utf8))

        let dest = work.appendingPathComponent("safe", isDirectory: true)
        await #expect(throws: TarKitError.self) {
            try await TarKit.Archive.extract(
                from: archive,
                options: TarKit.ExtractOptions(destination: dest))
        }
    }

    @Test func extractRejectsBackslashTraversal() async throws {
        // tar entries are POSIX-pathed, but a malicious producer can
        // still embed backslashes; treat them as separators so a `..`
        // can't slip through.
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appendingPathComponent("evil.tar")
        try writeArchive(
            at: archive,
            entryPath: "..\\..\\escape.txt",
            content: Data("nope".utf8))

        let dest = work.appendingPathComponent("safe", isDirectory: true)
        await #expect(throws: TarKitError.self) {
            try await TarKit.Archive.extract(
                from: archive,
                options: TarKit.ExtractOptions(destination: dest))
        }
    }

    @Test func extractKeepsRelativeSymlinkRelative() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        // Lay out: src/target.txt + src/link -> target.txt (relative).
        let src = work.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(
            at: src, withIntermediateDirectories: true)
        let realFile = src.appendingPathComponent("target.txt")
        try Data("hello\n".utf8).write(to: realFile)
        let linkPath = src.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: linkPath.path,
            withDestinationPath: "target.txt")

        let archive = work.appendingPathComponent("out.tar")
        try await TarKit.Archive.create(
            at: archive,
            paths: [src],
            options: TarKit.CreateOptions(followSymlinks: false))

        let extractDir = work.appendingPathComponent("out", isDirectory: true)
        try await TarKit.Archive.extract(
            from: archive,
            options: TarKit.ExtractOptions(destination: extractDir))

        let extractedLink = extractDir.appendingPathComponent("src/link")
        let target = try FileManager.default.destinationOfSymbolicLink(
            atPath: extractedLink.path)
        // Must remain "target.txt" — not the cwd-resolved absolute
        // path that URL(fileURLWithPath:) would have produced.
        #expect(target == "target.txt")
    }
}
