import Foundation
import Testing
@testable import ZipKit

// Direct libarchive access for hand-rolled malicious zips.
import struct Archive.ArchiveEntry
import class Archive.ArchiveWriter
import enum Archive.ArchiveFormat
import enum Archive.ArchiveFilter
import enum Archive.FileType

@Suite struct ZipKitSecurityTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zipkit-sec-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeArchive(
        at url: URL, entryPath: String, content: Data
    ) throws {
        let writer = try ArchiveWriter(
            path: url.path, format: .zip, filters: [.none])
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
        let archive = work.appendingPathComponent("evil.zip")
        try writeArchive(
            at: archive,
            entryPath: "../../escape.txt",
            content: Data("pwned\n".utf8))

        let dest = work.appendingPathComponent("safe", isDirectory: true)
        await #expect(throws: ZipKitError.self) {
            try await ZipKit.Archive.extract(
                from: archive,
                options: ZipKit.ExtractOptions(destination: dest))
        }
        let escapeAbove = work.appendingPathComponent("escape.txt")
        #expect(!FileManager.default.fileExists(atPath: escapeAbove.path))
    }

    @Test func extractRejectsAbsolutePath() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appendingPathComponent("evil.zip")
        try writeArchive(
            at: archive,
            entryPath: "/etc/oops",
            content: Data("nope".utf8))

        let dest = work.appendingPathComponent("safe", isDirectory: true)
        await #expect(throws: ZipKitError.self) {
            try await ZipKit.Archive.extract(
                from: archive,
                options: ZipKit.ExtractOptions(destination: dest))
        }
    }

    @Test func extractKeepsRelativeSymlinkRelative() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        let src = work.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(
            at: src, withIntermediateDirectories: true)
        try Data("hello\n".utf8).write(
            to: src.appendingPathComponent("target.txt"))
        let linkPath = src.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            atPath: linkPath.path,
            withDestinationPath: "target.txt")

        let archive = work.appendingPathComponent("out.zip")
        try await ZipKit.Archive.create(
            at: archive,
            paths: [src],
            options: ZipKit.CreateOptions(
                recursive: true, followSymlinks: false))

        let extractDir = work.appendingPathComponent("out", isDirectory: true)
        try await ZipKit.Archive.extract(
            from: archive,
            options: ZipKit.ExtractOptions(destination: extractDir))

        let extractedLink = extractDir.appendingPathComponent("src/link")
        let target = try FileManager.default.destinationOfSymbolicLink(
            atPath: extractedLink.path)
        #expect(target == "target.txt")
    }
}
