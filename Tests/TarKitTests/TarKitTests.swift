import Foundation
import Testing
@testable import TarKit

@Suite struct TarKitTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tarkit-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ content: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func roundTripPlainTar() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.tar")
        let source = workDir.appendingPathComponent("src", isDirectory: true)
        try writeFile("hello\n", at: source.appendingPathComponent("a.txt"))
        try writeFile("world\n",
                      at: source.appendingPathComponent("nested/b.txt"))

        try await Archive.create(at: archiveURL, paths: [source])

        let entries = try await Archive.list(at: archiveURL)
        let paths = Set(entries.map(\.path))
        #expect(paths.contains("src/"))
        #expect(paths.contains("src/a.txt"))
        #expect(paths.contains("src/nested/"))
        #expect(paths.contains("src/nested/b.txt"))

        let extractDir = workDir.appendingPathComponent("out", isDirectory: true)
        try await Archive.extract(
            from: archiveURL,
            options: ExtractOptions(destination: extractDir))

        let aPath = extractDir.appendingPathComponent("src/a.txt").path
        #expect(FileManager.default.fileExists(atPath: aPath))
        let aContent = try String(contentsOfFile: aPath, encoding: .utf8)
        #expect(aContent == "hello\n")
    }

    @Test func roundTripGzippedTar() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.tar.gz")
        let source = workDir.appendingPathComponent("src", isDirectory: true)
        try writeFile("payload\n",
                      at: source.appendingPathComponent("file.txt"))

        try await Archive.create(
            at: archiveURL,
            paths: [source],
            options: CreateOptions(compression: .gzip))

        // Verify the file actually starts with gzip magic bytes 1f 8b.
        let head = try FileHandle(forReadingFrom: archiveURL)
            .readData(ofLength: 2)
        #expect(head == Data([0x1f, 0x8b]))

        // libarchive auto-detects gzip on read — no flag needed.
        let entries = try await Archive.list(at: archiveURL)
        #expect(entries.contains { $0.path == "src/file.txt" })

        let extractDir = workDir.appendingPathComponent("out", isDirectory: true)
        try await Archive.extract(
            from: archiveURL,
            options: ExtractOptions(destination: extractDir))
        let content = try String(
            contentsOfFile: extractDir.appendingPathComponent("src/file.txt").path,
            encoding: .utf8)
        #expect(content == "payload\n")
    }

    @Test func extractRespectsStripComponents() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.tar")
        let source = workDir.appendingPathComponent("topdir/inner", isDirectory: true)
        try writeFile("deep\n",
                      at: source.appendingPathComponent("file.txt"))
        try await Archive.create(
            at: archiveURL,
            paths: [workDir.appendingPathComponent("topdir", isDirectory: true)])

        let extractDir = workDir.appendingPathComponent("flat", isDirectory: true)
        try await Archive.extract(
            from: archiveURL,
            options: ExtractOptions(destination: extractDir, stripComponents: 1))

        // With strip-components=1, "topdir/inner/file.txt" becomes "inner/file.txt".
        #expect(FileManager.default.fileExists(
            atPath: extractDir.appendingPathComponent("inner/file.txt").path))
        // The original top dir should not exist.
        #expect(!FileManager.default.fileExists(
            atPath: extractDir.appendingPathComponent("topdir").path))
    }

    @Test func listFromDataParsesGzipAutomatically() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.tar.gz")
        try writeFile("hi", at: workDir.appendingPathComponent("a.txt"))
        try await Archive.create(
            at: archiveURL,
            paths: [workDir.appendingPathComponent("a.txt")],
            options: CreateOptions(compression: .gzip))

        let bytes = try Data(contentsOf: archiveURL)
        let entries = try await Archive.list(data: bytes)
        #expect(entries.contains { $0.path == "a.txt" })
    }

    @Test func extractSkipsExistingWhenOverwriteFalse() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.tar")
        try writeFile("from-archive\n",
                      at: workDir.appendingPathComponent("a.txt"))
        try await Archive.create(
            at: archiveURL,
            paths: [workDir.appendingPathComponent("a.txt")])

        let extractDir = workDir.appendingPathComponent("out", isDirectory: true)
        try writeFile("preexisting\n",
                      at: extractDir.appendingPathComponent("a.txt"))

        try await Archive.extract(
            from: archiveURL,
            options: ExtractOptions(destination: extractDir, overwrite: false))

        let content = try String(
            contentsOfFile: extractDir.appendingPathComponent("a.txt").path,
            encoding: .utf8)
        #expect(content == "preexisting\n")
    }
}
