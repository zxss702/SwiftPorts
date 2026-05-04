import Foundation
import Testing
import ZipKit
@testable import GitHub

@Suite struct ZipExtractorTests {
    /// Build a small ZIP in memory via ZipKit (libarchive-backed),
    /// then round-trip via `ZipExtractor.extract`. Doesn't touch
    /// `Process` or any external binary — proves the in-process path
    /// works end-to-end on the host platform.
    @Test func extractsInMemoryArchive() async throws {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgh-zip-build-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // Lay out a tiny tree on disk and let ZipKit build a real
        // PKZIP archive — same code path the `zip` CLI exercises.
        let src = workDir.appendingPathComponent("src", isDirectory: true)
        let nested = src.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: nested,
                                                withIntermediateDirectories: true)
        try Data("hello from job 0\n".utf8).write(
            to: src.appendingPathComponent("0_first.txt"))
        try Data("hello from job 1\n".utf8).write(
            to: src.appendingPathComponent("1_second.txt"))
        try Data("nested\n".utf8).write(
            to: nested.appendingPathComponent("nested.txt"))

        let archiveURL = workDir.appendingPathComponent("in-memory.zip")
        try Archive.create(
            at: archiveURL,
            paths: [src],
            options: CreateOptions(recursive: true))
        let zipData = try Data(contentsOf: archiveURL)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgh-zip-test-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }

        try await ZipExtractor.extract(zipData: zipData, into: dest)

        #expect(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("src/0_first.txt").path))
        #expect(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("src/subdir/nested.txt").path))
        let first = try String(
            contentsOf: dest.appendingPathComponent("src/0_first.txt"),
            encoding: .utf8)
        #expect(first == "hello from job 0\n")
    }
}
