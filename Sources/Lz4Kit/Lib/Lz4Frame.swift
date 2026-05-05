import Foundation

/// Standard `.lz4` v1.6.x frame format encoder + decoder. Wraps
/// raw LZ4 blocks with the magic / frame descriptor / EndMark
/// scaffolding so output is interoperable with system `lz4(1)`
/// and other reference implementations.
///
/// We emit a minimal frame: independent 64 KB blocks, no per-block
/// or content checksums, no content size, no dict ID. That's the
/// simplest valid frame and decompresses everywhere.
internal enum Lz4Frame {
    /// 4-byte little-endian magic: 0x184D2204.
    static let magic: [UInt8] = [0x04, 0x22, 0x4D, 0x18]
    /// 4-byte EndMark: 0x00000000.
    static let endMark: [UInt8] = [0x00, 0x00, 0x00, 0x00]

    /// FLG byte. Bits, MSB→LSB:
    ///   7-6: version = 01
    ///   5: B.Indep = 1 (blocks are independent)
    ///   4: B.Checksum = 0 (no per-block checksum)
    ///   3: C.Size = 0 (no content size)
    ///   2: C.Checksum = 0 (no content checksum)
    ///   1: reserved = 0
    ///   0: Dict ID = 0
    static let flg: UInt8 = 0b01100000  // 0x60

    /// BD byte. Bits 6-4 = block-max-size (4 = 64 KB).
    static let bd: UInt8 = 0b01000000  // 0x40

    /// Block size cap that matches BD = 4 (64 KB). The encoder splits
    /// input on this boundary; the decoder uses it as the per-block
    /// output buffer size.
    static let blockSize: Int = 64 * 1024

    /// Compute the 1-byte header checksum: bits 8-15 of xxh32 over
    /// FLG || BD (|| optional extras, none in our minimal frame).
    static let headerChecksum: UInt8 = UInt8((XXHash32.hash([flg, bd]) >> 8) & 0xff)

    /// Build a complete `.lz4` frame from a list of blocks.
    static func build(blocks: [Block]) -> Data {
        var out = Data()
        out.append(contentsOf: magic)
        out.append(flg)
        out.append(bd)
        out.append(headerChecksum)
        for block in blocks {
            var sizeWord = UInt32(block.payload.count)
            if block.uncompressed { sizeWord |= 0x80000000 }
            out.append(contentsOf: writeLE32(sizeWord))
            out.append(block.payload)
        }
        out.append(contentsOf: endMark)
        return out
    }

    /// Iterate the blocks of `data`, validating the frame header on
    /// the way in. The closure gets `(payload, isUncompressed)`
    /// for each block; raw or compressed bytes are passed straight
    /// through so the caller can route them through the platform's
    /// LZ4 block decoder. Cooperatively cancellable: each block
    /// boundary checks `Task.isCancelled`.
    static func parseBlocks(
        _ data: Data,
        body: (Data, Bool) async throws -> Void
    ) async throws {
        guard data.count >= 7 else {
            throw Lz4KitError.decompressionFailed("frame too short")
        }
        // Slice into the data range so absolute byte indexing is
        // local to this view (Data's `startIndex` may not be 0
        // when sliced from a parent Data).
        let bytes = [UInt8](data)
        guard Array(bytes.prefix(4)) == magic else {
            throw Lz4KitError.decompressionFailed(
                "not an .lz4 frame (bad magic)")
        }
        let flgByte = bytes[4]
        let bdByte = bytes[5]
        let hcByte = bytes[6]
        let expectedHC = UInt8((XXHash32.hash([flgByte, bdByte]) >> 8) & 0xff)
        guard hcByte == expectedHC else {
            throw Lz4KitError.decompressionFailed(
                "frame header checksum mismatch")
        }
        // We only support the minimal frame layout we emit. Reject
        // ContentSize (FLG bit 3) and DictID (FLG bit 0) for now —
        // their presence shifts subsequent block offsets.
        if (flgByte & 0x09) != 0 {
            throw Lz4KitError.decompressionFailed(
                "frame uses ContentSize / DictID (not supported)")
        }
        // Block-checksum and content-checksum (bits 4 and 2) we
        // tolerate on read by ignoring them — checksums are skipped
        // since we don't compute xxh32 on the inner bytes here.
        let hasBlockChecksum = (flgByte & 0x10) != 0
        let hasContentChecksum = (flgByte & 0x04) != 0

        var i = 7
        while i + 4 <= bytes.count {
            try Task.checkCancellation()
            let sizeWord = readLE32(bytes, i)
            i += 4
            if sizeWord == 0 {
                // EndMark — optional content-checksum trailer follows
                // if FLG bit 2 was set; we don't validate it.
                if hasContentChecksum {
                    guard i + 4 <= bytes.count else {
                        throw Lz4KitError.decompressionFailed(
                            "frame missing content checksum")
                    }
                    i += 4
                }
                return
            }
            let uncompressed = (sizeWord & 0x80000000) != 0
            let payloadSize = Int(sizeWord & 0x7fffffff)
            guard i + payloadSize <= bytes.count else {
                throw Lz4KitError.decompressionFailed(
                    "frame truncated mid-block")
            }
            let payload = Data(bytes[i..<(i + payloadSize)])
            try await body(payload, uncompressed)
            i += payloadSize
            if hasBlockChecksum {
                guard i + 4 <= bytes.count else {
                    throw Lz4KitError.decompressionFailed(
                        "frame truncated before block checksum")
                }
                i += 4   // skip; we don't validate
            }
        }
        throw Lz4KitError.decompressionFailed("frame missing EndMark")
    }

    struct Block {
        var payload: Data
        var uncompressed: Bool
    }

    @inline(__always)
    private static func writeLE32(_ v: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v),
         UInt8(truncatingIfNeeded: v >> 8),
         UInt8(truncatingIfNeeded: v >> 16),
         UInt8(truncatingIfNeeded: v >> 24)]
    }

    @inline(__always)
    private static func readLE32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i])
            | (UInt32(b[i + 1]) << 8)
            | (UInt32(b[i + 2]) << 16)
            | (UInt32(b[i + 3]) << 24)
    }
}
