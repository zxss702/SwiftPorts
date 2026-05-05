import Foundation
import Testing
@testable import GzipKit

@Suite struct GzipKitTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gzipkit-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripData() async throws {
        let original = Data("the quick brown fox jumps over the lazy dog\n".utf8)
        let compressed = try await Gzip.compress(original)
        // Output should start with gzip magic 1f 8b.
        #expect(compressed.starts(with: [0x1f, 0x8b]))
        // And be smaller than the original… well, for this short string it
        // probably isn't, but it should at least be parseable.
        let decompressed = try await Gzip.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func roundTripBigPayload() async throws {
        // Random-ish 256 KB blob — large enough to actually exercise
        // deflate's window.
        var bytes = [UInt8]()
        bytes.reserveCapacity(256 * 1024)
        for i in 0..<(256 * 1024) {
            bytes.append(UInt8((i * 31) & 0xff))
        }
        let original = Data(bytes)
        let compressed = try await Gzip.compress(original)
        #expect(compressed.count < original.count)  // should compress
        let decompressed = try await Gzip.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func compressFileProducesGzSuffix() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("payload.txt")
        try Data("payload\n".utf8).write(to: source)

        let dest = try await Gzip.compressFile(at: source, keepInput: true)
        #expect(dest.path == source.path + ".gz")
        let head = try FileHandle(forReadingFrom: dest).readData(ofLength: 2)
        #expect(head == Data([0x1f, 0x8b]))
        // Original kept because keepInput: true.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func decompressFileStripsGzSuffix() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("data.txt")
        let original = Data("decompress me\n".utf8)
        try original.write(to: source)
        _ = try await Gzip.compressFile(at: source)
        // Original removed; .gz exists.
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let gz = work.appendingPathComponent("data.txt.gz")

        let dest = try await Gzip.decompressFile(at: gz)
        #expect(dest.path == source.path)
        let restored = try Data(contentsOf: dest)
        #expect(restored == original)
        #expect(!FileManager.default.fileExists(atPath: gz.path))
    }

    @Test func decompressFileRefusesUnknownSuffix() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("file.bin")
        try Data([0x1f, 0x8b]).write(to: source)
        await #expect(throws: GzipKitError.self) {
            _ = try await Gzip.decompressFile(at: source)
        }
    }

    @Test func decompressFileMapsTgzToTar() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        // Pre-compress a fake .tar by hand — content doesn't have to
        // actually be tar-shaped; gzip just decompresses bytes.
        let body = Data(repeating: 0x42, count: 1024)
        let compressed = try await Gzip.compress(body)
        let tgz = work.appendingPathComponent("bundle.tgz")
        try compressed.write(to: tgz)

        let dest = try await Gzip.decompressFile(at: tgz)
        #expect(dest.path == work.appendingPathComponent("bundle.tar").path)
    }
}
