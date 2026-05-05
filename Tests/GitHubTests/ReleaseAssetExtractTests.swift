import Foundation
import Testing
import TarKit
import XzKit
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

    // libarchive's bz2 / zstd filters are gated to platforms where
    // the system libraries ship (per the swift-archive
    // per-platform-traits fork) — macOS / Linux / Windows. iOS /
    // tvOS / watchOS / visionOS / Android do not compile those
    // filters into CArchive, so write / read of those compressed
    // tarballs throws `archiveOpenFailed`. Gate those tests.
    //
    // tar.xz is treated specially: XzKit has an Apple-libcompression
    // backend, so we have a dedicated `extractTarXzEndToEnd` test
    // below that builds the fixture through the chain (TarKit plain
    // tar → XzKit compress) and exercises the `gh release download`
    // dispatcher's chained-decompression branch on iOS too.
    #if os(macOS) || os(Linux) || os(Windows)
    @Test func extractTarBz2EndToEnd() throws {
        try roundTripTarball(compression: .bzip2)
    }

    @Test func extractTarZstEndToEnd() throws {
        try roundTripTarball(compression: .zstd)
    }
    #endif

    @Test func extractTarXzEndToEnd() throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-extract-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let payloadDir = work.appendingPathComponent("repo-1.2.3", isDirectory: true)
        try FileManager.default.createDirectory(
            at: payloadDir, withIntermediateDirectories: true)
        try Data("# README\n".utf8).write(
            to: payloadDir.appendingPathComponent("README.md"))

        // On iOS / tvOS / watchOS / visionOS libarchive can't write
        // .xz natively (the lzma trait isn't compiled in there); on
        // those platforms we have to chain plain-tar + XzKit. The
        // happy path on macOS / Linux / Windows uses TarKit's
        // libarchive xz filter directly and produces an identical
        // .xz container.
        let archive = work.appendingPathComponent("repo-1.2.3.tar.xz")
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        let plainTar = work.appendingPathComponent("repo-1.2.3.tar")
        try TarKit.Archive.create(at: plainTar, paths: [payloadDir])
        let plainBytes = try Data(contentsOf: plainTar)
        let xzBytes = try XzKit.Xz.compress(plainBytes)
        try xzBytes.write(to: archive)
        #else
        try TarKit.Archive.create(
            at: archive,
            paths: [payloadDir],
            options: TarKit.CreateOptions(compression: .xz))
        #endif

        let dest = work.appendingPathComponent("out", isDirectory: true)
        try ArchiveFormatDetector.extract(
            archive: archive, format: .tar, into: dest)

        let readme = dest.appendingPathComponent("repo-1.2.3/README.md")
        #expect(FileManager.default.fileExists(atPath: readme.path))
        let contents = try String(contentsOf: readme, encoding: .utf8)
        #expect(contents == "# README\n")
    }

    /// Build a tar.<compression> on disk, run it through the
    /// dispatcher, verify a known file decodes back. Covers the
    /// bz2 / xz / zst arms unlocked by enabling all four
    /// swift-archive traits via the per-platform-traits fork.
    private func roundTripTarball(
        compression: TarKit.Compression
    ) throws {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-extract-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let payloadDir = work.appendingPathComponent("repo-1.2.3", isDirectory: true)
        try FileManager.default.createDirectory(
            at: payloadDir, withIntermediateDirectories: true)
        try Data("# README\n".utf8).write(
            to: payloadDir.appendingPathComponent("README.md"))

        let suffix: String
        switch compression {
        case .bzip2: suffix = ".tar.bz2"
        case .xz:    suffix = ".tar.xz"
        case .zstd:  suffix = ".tar.zst"
        default:     suffix = ".tar"
        }
        let archive = work.appendingPathComponent("repo-1.2.3" + suffix)
        try TarKit.Archive.create(
            at: archive,
            paths: [payloadDir],
            options: TarKit.CreateOptions(compression: compression))

        let dest = work.appendingPathComponent("out", isDirectory: true)
        try ArchiveFormatDetector.extract(
            archive: archive, format: .tar, into: dest)

        let readme = dest.appendingPathComponent("repo-1.2.3/README.md")
        #expect(FileManager.default.fileExists(atPath: readme.path))
        let contents = try String(contentsOf: readme, encoding: .utf8)
        #expect(contents == "# README\n")
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
