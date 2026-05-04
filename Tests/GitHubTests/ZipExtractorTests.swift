// Windows: ZIPFoundation's MemoryFile fallback uses `tmpfile()` (no
// `funopen`/`fopencookie` available there), so writes go to disk and
// the `Archive.data` getter never sees them. In-memory archive tests
// can't run until we wire up a CreateFileMapping-backed FILE stream;
// gate the suite to non-Windows for now.
#if !os(Windows)
import Foundation
import Testing
import ZIPFoundation
@testable import GitHub

@Suite struct ZipExtractorTests {
    /// Build a small ZIP in memory, then round-trip via
    /// `ZipExtractor.extract`. Doesn't touch Process or any external
    /// binary — proves the in-process path works end-to-end on the
    /// host platform.
    @Test func extractsInMemoryArchive() async throws {
        let archive = try Archive(accessMode: .create)
        try addEntry(to: archive, path: "0_first.txt",
                     content: "hello from job 0\n")
        try addEntry(to: archive, path: "1_second.txt",
                     content: "hello from job 1\n")
        try addEntry(to: archive, path: "subdir/nested.txt",
                     content: "nested\n")
        let zipData = try #require(archive.data)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftgh-zip-test-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dest) }

        try await ZipExtractor.extract(zipData: zipData, into: dest)

        #expect(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("0_first.txt").path))
        #expect(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("subdir/nested.txt").path))
        let first = try String(
            contentsOf: dest.appendingPathComponent("0_first.txt"),
            encoding: .utf8)
        #expect(first == "hello from job 0\n")
    }

    private func addEntry(
        to archive: Archive, path: String, content: String
    ) throws {
        let bytes = Data(content.utf8)
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(bytes.count),
            compressionMethod: .deflate,
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, bytes.count)
                return bytes.subdata(in: start..<end)
            })
    }
}

#endif
