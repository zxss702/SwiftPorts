// libbz2/liblzma/libzstd are not in the iOS / tvOS / watchOS / visionOS
// SDK. Gate the whole module to platforms where the system library is
// available; iOS support requires vendoring sources.
#if os(macOS) || os(Linux) || os(Windows)

import Foundation
import Testing
@testable import ZstdKit

@Suite struct ZstdKitTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zstdkit-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripData() async throws {
        let original = Data(
            "the quick brown fox jumps over the lazy dog\n".utf8)
        let compressed = try await Zstd.compress(original)
        // zstd magic: 28 B5 2F FD (little-endian for 0xFD2FB528).
        #expect(compressed.starts(with: [0x28, 0xB5, 0x2F, 0xFD]))
        let decompressed = try await Zstd.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func roundTripBigPayload() async throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(256 * 1024)
        for i in 0..<(256 * 1024) {
            bytes.append(UInt8((i * 31) & 0xff))
        }
        let original = Data(bytes)
        let compressed = try await Zstd.compress(original)
        #expect(compressed.count < original.count)
        let decompressed = try await Zstd.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func compressFileProducesZstSuffix() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("payload.txt")
        try Data("payload\n".utf8).write(to: source)

        let dest = try await Zstd.compressFile(at: source, keepInput: true)
        #expect(dest.path == source.path + ".zst")
        let head = try FileHandle(forReadingFrom: dest).readData(ofLength: 4)
        #expect(head == Data([0x28, 0xB5, 0x2F, 0xFD]))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func decompressFileStripsZstSuffix() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("data.txt")
        let original = Data("decompress me\n".utf8)
        try original.write(to: source)
        _ = try await Zstd.compressFile(at: source)
        let zst = work.appendingPathComponent("data.txt.zst")
        let dest = try await Zstd.decompressFile(at: zst)
        #expect(dest.path == source.path)
        let restored = try Data(contentsOf: dest)
        #expect(restored == original)
    }

    @Test func decompressFileMapsTzstToTar() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let body = Data(repeating: 0x42, count: 1024)
        let compressed = try await Zstd.compress(body)
        let tzst = work.appendingPathComponent("bundle.tzst")
        try compressed.write(to: tzst)
        let dest = try await Zstd.decompressFile(at: tzst)
        #expect(dest.path == work.appendingPathComponent("bundle.tar").path)
    }

    @Test func decompressRejectsTruncated() async throws {
        let original = Data("hello zstd world\n".utf8)
        let compressed = try await Zstd.compress(original)
        let truncated = compressed.prefix(compressed.count - 4)
        await #expect(throws: ZstdKitError.self) {
            _ = try await Zstd.decompress(truncated)
        }
    }

    @Test func decompressRejectsEmptyInput() async throws {
        // An empty Data isn't a valid zstd frame; the streaming
        // decoder previously returned Data() silently because the
        // loop never iterated.
        await #expect(throws: ZstdKitError.self) {
            _ = try await Zstd.decompress(Data())
        }
    }
}

#endif // platform gate
