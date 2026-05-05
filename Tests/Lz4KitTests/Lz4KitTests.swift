#if canImport(Compression) || os(Linux) || os(Windows)
import Foundation
import Testing
@testable import Lz4Kit

@Suite struct Lz4KitTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lz4kit-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripData() async throws {
        let original = Data("the quick brown fox jumps over the lazy dog\n".utf8)
        let compressed = try await Lz4.compress(original)
        // .lz4 magic 04 22 4D 18.
        #expect(compressed.starts(with: [0x04, 0x22, 0x4D, 0x18]))
        let decompressed = try await Lz4.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func roundTripBigPayload() async throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(256 * 1024)
        for i in 0..<(256 * 1024) {
            bytes.append(UInt8((i * 31) & 0xff))
        }
        let original = Data(bytes)
        let compressed = try await Lz4.compress(original)
        // Compresses well because the input cycles through 256
        // distinct bytes — many repeated 256-byte blocks.
        #expect(compressed.count < original.count)
        let decompressed = try await Lz4.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func roundTripIncompressible() async throws {
        // Random-ish bytes — LZ4 can't shrink, so blocks should
        // emit uncompressed (high-bit set in the size word). Tests
        // the engine's choose-uncompressed-when-larger path.
        var bytes = [UInt8]()
        bytes.reserveCapacity(32 * 1024)
        var seed: UInt32 = 0x12345678
        for _ in 0..<(32 * 1024) {
            seed = seed &* 1103515245 &+ 12345
            bytes.append(UInt8((seed >> 16) & 0xff))
        }
        let original = Data(bytes)
        let compressed = try await Lz4.compress(original)
        let decompressed = try await Lz4.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func compressFileProducesLz4Suffix() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("payload.txt")
        try Data("payload\n".utf8).write(to: source)

        let dest = try await Lz4.compressFile(at: source, keepInput: true)
        #expect(dest.path == source.path + ".lz4")
        let head = try FileHandle(forReadingFrom: dest).readData(ofLength: 4)
        #expect(head == Data([0x04, 0x22, 0x4D, 0x18]))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func decompressFileStripsLz4Suffix() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("data.txt")
        let original = Data("decompress me\n".utf8)
        try original.write(to: source)
        _ = try await Lz4.compressFile(at: source)
        let lz4 = work.appendingPathComponent("data.txt.lz4")

        let dest = try await Lz4.decompressFile(at: lz4)
        #expect(dest.path == source.path)
        let restored = try Data(contentsOf: dest)
        #expect(restored == original)
    }

    @Test func decompressFileMapsTlz4ToTar() async throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let body = Data(repeating: 0x42, count: 1024)
        let compressed = try await Lz4.compress(body)
        let tlz4 = work.appendingPathComponent("bundle.tlz4")
        try compressed.write(to: tlz4)
        let dest = try await Lz4.decompressFile(at: tlz4)
        #expect(dest.path == work.appendingPathComponent("bundle.tar").path)
    }

    @Test func decompressRejectsTruncated() async throws {
        let original = Data("hello lz4 world\n".utf8)
        let compressed = try await Lz4.compress(original)
        let truncated = compressed.prefix(compressed.count - 4)
        await #expect(throws: Lz4KitError.self) {
            _ = try await Lz4.decompress(truncated)
        }
    }

    @Test func decompressRejectsEmptyInput() async throws {
        await #expect(throws: Lz4KitError.self) {
            _ = try await Lz4.decompress(Data())
        }
    }

    @Test func decompressRejectsBadMagic() async throws {
        await #expect(throws: Lz4KitError.self) {
            _ = try await Lz4.decompress(Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]))
        }
    }
}
#endif
