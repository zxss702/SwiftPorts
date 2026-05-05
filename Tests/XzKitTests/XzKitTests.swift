// libbz2/liblzma/libzstd are not in the iOS / tvOS / watchOS / visionOS
// SDK. Gate the whole module to platforms where the system library is
// available; iOS support requires vendoring sources.
#if os(macOS) || os(Linux) || os(Windows)

import Foundation
import Testing
@testable import XzKit

@Suite struct XzKitTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xzkit-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripData() throws {
        let original = Data(
            "the quick brown fox jumps over the lazy dog\n".utf8)
        let compressed = try Xz.compress(original)
        // xz magic: FD 37 7A 58 5A 00 ('\xfd7zXZ\0')
        #expect(compressed.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]))
        let decompressed = try Xz.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func roundTripBigPayload() throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(256 * 1024)
        for i in 0..<(256 * 1024) {
            bytes.append(UInt8((i * 31) & 0xff))
        }
        let original = Data(bytes)
        let compressed = try Xz.compress(original)
        #expect(compressed.count < original.count)
        let decompressed = try Xz.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func compressFileProducesXzSuffix() throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("payload.txt")
        try Data("payload\n".utf8).write(to: source)

        let dest = try Xz.compressFile(at: source, keepInput: true)
        #expect(dest.path == source.path + ".xz")
        let head = try FileHandle(forReadingFrom: dest).readData(ofLength: 6)
        #expect(head == Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func decompressFileStripsXzSuffix() throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("data.txt")
        let original = Data("decompress me\n".utf8)
        try original.write(to: source)
        _ = try Xz.compressFile(at: source)
        let xz = work.appendingPathComponent("data.txt.xz")
        let dest = try Xz.decompressFile(at: xz)
        #expect(dest.path == source.path)
        let restored = try Data(contentsOf: dest)
        #expect(restored == original)
    }

    @Test func decompressFileMapsTxzToTar() throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let body = Data(repeating: 0x42, count: 1024)
        let compressed = try Xz.compress(body)
        let txz = work.appendingPathComponent("bundle.txz")
        try compressed.write(to: txz)
        let dest = try Xz.decompressFile(at: txz)
        #expect(dest.path == work.appendingPathComponent("bundle.tar").path)
    }

    @Test func decompressRejectsTruncated() throws {
        let original = Data("hello xz world\n".utf8)
        let compressed = try Xz.compress(original)
        let truncated = compressed.prefix(compressed.count - 4)
        #expect(throws: XzKitError.self) {
            _ = try Xz.decompress(truncated)
        }
    }
}

#endif // platform gate
