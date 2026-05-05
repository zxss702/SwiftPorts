import Foundation
import Testing
import TarKit
import ZipKit
@testable import GhCommand

@Suite struct ReleaseAssetExtractTests {
    @Test func detectsZipByExtension() {
        #expect(ArchiveFormatDetector.detect(name: "foo.zip") == .zip)
        #expect(ArchiveFormatDetector.detect(name: "FOO.ZIP") == .zip)
    }

    @Test func detectsTarVariants() {
        #expect(ArchiveFormatDetector.detect(name: "x.tar") == .tar)
        #expect(ArchiveFormatDetector.detect(name: "x.tar.gz") == .tar)
        #expect(ArchiveFormatDetector.detect(name: "x.tgz") == .tar)
        #expect(ArchiveFormatDetector.detect(name: "x.tar.xz") == .tar)
        #expect(ArchiveFormatDetector.detect(name: "x.tar.zst") == .tar)
    }

    @Test func returnsNilForUnknownSuffix() {
        #expect(ArchiveFormatDetector.detect(name: "foo.dmg") == nil)
        #expect(ArchiveFormatDetector.detect(name: "foo") == nil)
        #expect(ArchiveFormatDetector.detect(name: "foo.exe") == nil)
    }

    @Test func strippedBaseNameDropsSuffixes() {
        #expect(ArchiveFormatDetector.strippedBaseName("foo-1.2.3.tar.gz")
                == "foo-1.2.3")
        #expect(ArchiveFormatDetector.strippedBaseName("payload.tgz")
                == "payload")
        #expect(ArchiveFormatDetector.strippedBaseName("bundle.zip")
                == "bundle")
        #expect(ArchiveFormatDetector.strippedBaseName("plain.bin")
                == "plain.bin")
    }

    @Test func extractTarGzEndToEnd() throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-extract-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // Build a tiny tar.gz "release asset" on disk.
        let payloadDir = work.appendingPathComponent("repo-1.2.3", isDirectory: true)
        try FileManager.default.createDirectory(
            at: payloadDir, withIntermediateDirectories: true)
        try Data("# README\n".utf8).write(
            to: payloadDir.appendingPathComponent("README.md"))
        let archive = work.appendingPathComponent("repo-1.2.3.tar.gz")
        try TarKit.Archive.create(
            at: archive,
            paths: [payloadDir],
            options: TarKit.CreateOptions(compression: .gzip))

        // Extract via the same routine the gh CLI uses.
        let dest = work.appendingPathComponent("out", isDirectory: true)
        try ArchiveFormatDetector.extract(
            archive: archive, format: .tar, into: dest)

        let readme = dest.appendingPathComponent("repo-1.2.3/README.md")
        #expect(FileManager.default.fileExists(atPath: readme.path))
        let contents = try String(contentsOf: readme, encoding: .utf8)
        #expect(contents == "# README\n")
    }

    @Test func extractZipEndToEnd() throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-extract-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let payloadDir = work.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(
            at: payloadDir, withIntermediateDirectories: true)
        try Data("hello\n".utf8).write(
            to: payloadDir.appendingPathComponent("a.txt"))
        let archive = work.appendingPathComponent("payload.zip")
        try ZipKit.Archive.create(
            at: archive, paths: [payloadDir],
            options: ZipKit.CreateOptions(recursive: true))

        let dest = work.appendingPathComponent("out", isDirectory: true)
        try ArchiveFormatDetector.extract(
            archive: archive, format: .zip, into: dest)

        let extracted = dest.appendingPathComponent("payload/a.txt")
        #expect(FileManager.default.fileExists(atPath: extracted.path))
    }
}
