import Foundation
import Testing
@testable import GzipKit

@Suite struct GzipKitSecurityTests {
    @Test func decompressRejectsTruncatedStream() async throws {
        let original = Data(
            "the quick brown fox jumps over the lazy dog\n".utf8)
        let compressed = try await Gzip.compress(original)
        // Slice off the trailing CRC + ISIZE trailer (last 8 bytes of
        // a gzip stream) so inflate runs out of input mid-stream.
        // Z_BUF_ERROR used to silently return partial bytes; it now
        // throws GzipKitError.decompressionFailed.
        let truncated = compressed.prefix(compressed.count - 8)
        await #expect(throws: GzipKitError.self) {
            _ = try await Gzip.decompress(truncated)
        }
    }

    @Test func decompressRejectsHalfStream() async throws {
        // More aggressive: cut the compressed stream in half. Should
        // also error rather than return whatever inflate happened to
        // produce up to that point.
        let original = Data(repeating: 0x42, count: 8 * 1024)
        let compressed = try await Gzip.compress(original)
        let half = compressed.prefix(compressed.count / 2)
        await #expect(throws: GzipKitError.self) {
            _ = try await Gzip.decompress(half)
        }
    }
}
