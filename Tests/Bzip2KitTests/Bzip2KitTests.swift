// libbz2/liblzma/libzstd are not in the iOS / tvOS / watchOS / visionOS
// SDK. Gate the whole module to platforms where the system library is
// available; iOS support requires vendoring sources.
#if os(macOS) || os(Linux) || os(Windows)

import Foundation
import Testing
@testable import Bzip2Kit

@Suite struct Bzip2KitTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bzip2kit-test-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripData() throws {
        let original = Data("the quick brown fox jumps over the lazy dog\n".utf8)
        let compressed = try Bzip2.compress(original)
        // bzip2 magic: 0x42 0x5A 0x68 ('BZh')
        #expect(compressed.starts(with: [0x42, 0x5A, 0x68]))
        let decompressed = try Bzip2.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func roundTripBigPayload() throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(256 * 1024)
        for i in 0..<(256 * 1024) {
            bytes.append(UInt8((i * 31) & 0xff))
        }
        let original = Data(bytes)
        let compressed = try Bzip2.compress(original)
        #expect(compressed.count < original.count)
        let decompressed = try Bzip2.decompress(compressed)
        #expect(decompressed == original)
    }

    @Test func compressFileProducesBz2Suffix() throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("payload.txt")
        try Data("payload\n".utf8).write(to: source)

        let dest = try Bzip2.compressFile(at: source, keepInput: true)
        #expect(dest.path == source.path + ".bz2")
        let head = try FileHandle(forReadingFrom: dest).readData(ofLength: 3)
        #expect(head == Data([0x42, 0x5A, 0x68]))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func decompressFileStripsBz2Suffix() throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = work.appendingPathComponent("data.txt")
        let original = Data("decompress me\n".utf8)
        try original.write(to: source)
        _ = try Bzip2.compressFile(at: source)
        let bz2 = work.appendingPathComponent("data.txt.bz2")

        let dest = try Bzip2.decompressFile(at: bz2)
        #expect(dest.path == source.path)
        let restored = try Data(contentsOf: dest)
        #expect(restored == original)
    }

    @Test func decompressFileMapsTbz2ToTar() throws {
        let work = tempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let body = Data(repeating: 0x42, count: 1024)
        let compressed = try Bzip2.compress(body)
        let tbz2 = work.appendingPathComponent("bundle.tbz2")
        try compressed.write(to: tbz2)
        let dest = try Bzip2.decompressFile(at: tbz2)
        #expect(dest.path == work.appendingPathComponent("bundle.tar").path)
    }

    @Test func decompressRejectsTruncated() throws {
        let original = Data("hello bzip2 world\n".utf8)
        let compressed = try Bzip2.compress(original)
        let truncated = compressed.prefix(compressed.count - 4)
        #expect(throws: Bzip2KitError.self) {
            _ = try Bzip2.decompress(truncated)
        }
    }
}

#endif // platform gate
