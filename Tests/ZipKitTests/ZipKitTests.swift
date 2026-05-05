import Foundation
import Testing
@testable import ZipKit

@Suite struct ArchiveTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zipkit-test-\(UUID().uuidString)",
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

    @Test func roundTripCreateExtractList() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.zip")

        let source = workDir.appendingPathComponent("src", isDirectory: true)
        try writeFile("hello\n", at: source.appendingPathComponent("a.txt"))
        try writeFile("world\n", at: source.appendingPathComponent("nested/b.txt"))

        try await Archive.create(
            at: archiveURL,
            paths: [source],
            options: CreateOptions(recursive: true))

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

    @Test func extractRespectsJunkPaths() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.zip")
        let source = workDir.appendingPathComponent("src/nested/deep.txt")
        try writeFile("payload\n", at: source)
        try await Archive.create(
            at: archiveURL,
            paths: [workDir.appendingPathComponent("src", isDirectory: true)],
            options: CreateOptions(recursive: true))

        let extractDir = workDir.appendingPathComponent("flat", isDirectory: true)
        try await Archive.extract(
            from: archiveURL,
            options: ExtractOptions(destination: extractDir, junkPaths: true))
        // Junked: deep.txt should land at root.
        #expect(FileManager.default.fileExists(
            atPath: extractDir.appendingPathComponent("deep.txt").path))
        // The directory entry itself junks down to nothing (entry path
        // becomes "" which we skip), so no nested folder should exist.
        #expect(!FileManager.default.fileExists(
            atPath: extractDir.appendingPathComponent("nested").path))
    }

    @Test func extractFiltersByIncludesAndExcludes() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.zip")
        let source = workDir.appendingPathComponent("src", isDirectory: true)
        try writeFile("a", at: source.appendingPathComponent("keep.txt"))
        try writeFile("b", at: source.appendingPathComponent("skip.log"))
        try writeFile("c", at: source.appendingPathComponent("README.md"))
        try await Archive.create(
            at: archiveURL,
            paths: [source],
            options: CreateOptions(recursive: true))

        let extractDir = workDir.appendingPathComponent("out", isDirectory: true)
        try await Archive.extract(
            from: archiveURL,
            options: ExtractOptions(
                destination: extractDir,
                includes: ["*.txt", "*.md"],
                excludes: []))

        #expect(FileManager.default.fileExists(
            atPath: extractDir.appendingPathComponent("src/keep.txt").path))
        #expect(!FileManager.default.fileExists(
            atPath: extractDir.appendingPathComponent("src/skip.log").path))
    }

    @Test func testIntegrityPasses() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.zip")
        let source = workDir.appendingPathComponent("a.txt")
        try writeFile("the quick brown fox\n", at: source)
        try await Archive.create(at: archiveURL, paths: [source])
        let entries = try await Archive.test(at: archiveURL)
        #expect(entries.contains { $0.path == "a.txt" })
    }

    @Test func readSingleEntry() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.zip")
        try writeFile("payload contents\n",
                      at: workDir.appendingPathComponent("a.txt"))
        try await Archive.create(
            at: archiveURL,
            paths: [workDir.appendingPathComponent("a.txt")])
        let bytes = try await Archive.read(entry: "a.txt", from: archiveURL)
        #expect(String(data: bytes, encoding: .utf8) == "payload contents\n")
    }

    @Test func readMissingEntryThrows() async throws {
        let workDir = tempDir()
        defer { try? FileManager.default.removeItem(at: workDir) }
        let archiveURL = workDir.appendingPathComponent("out.zip")
        try writeFile("x", at: workDir.appendingPathComponent("only.txt"))
        try await Archive.create(
            at: archiveURL,
            paths: [workDir.appendingPathComponent("only.txt")])
        await #expect(throws: ZipKitError.self) {
            _ = try await Archive.read(entry: "missing.txt", from: archiveURL)
        }
    }
}

@Suite struct GlobMatcherTests {
    @Test func matchesStarAndQuestion() {
        #expect(GlobMatcher.matches(pattern: "*.txt", name: "a.txt"))
        #expect(!GlobMatcher.matches(pattern: "*.txt", name: "a.log"))
        #expect(GlobMatcher.matches(pattern: "a?c", name: "abc"))
        #expect(!GlobMatcher.matches(pattern: "a?c", name: "abbc"))
        #expect(GlobMatcher.matches(pattern: "*", name: "anything"))
        #expect(GlobMatcher.matches(pattern: "*", name: ""))
    }

    @Test func caseInsensitive() {
        #expect(!GlobMatcher.matches(pattern: "*.TXT", name: "a.txt"))
        #expect(GlobMatcher.matches(
            pattern: "*.TXT", name: "a.txt", caseInsensitive: true))
    }

    @Test func matchesAny() {
        #expect(GlobMatcher.matchesAny(
            patterns: ["*.swift", "*.md"], name: "README.md"))
        #expect(!GlobMatcher.matchesAny(
            patterns: ["*.swift", "*.md"], name: "image.png"))
        #expect(!GlobMatcher.matchesAny(patterns: [], name: "anything"))
    }
}
