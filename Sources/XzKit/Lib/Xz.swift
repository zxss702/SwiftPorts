// libbz2/liblzma/libzstd are not in the iOS / tvOS / watchOS / visionOS
// SDK. Gate the whole module to platforms where the system library is
// available; iOS support requires vendoring sources.
#if os(macOS) || os(Linux) || os(Windows)

import Foundation
import CLZMA

/// Pure-Swift `xz(1)` engine — single-file compression / decompression
/// via liblzma's streaming API (`lzma_easy_encoder` / `lzma_stream_decoder`
/// + `lzma_code`).
public enum Xz {

    private static let chunkSize = 64 * 1024
    /// Encoder preset, 0..9. 6 is liblzma's default; matches `xz -6`.
    public static let defaultPreset: UInt32 = 6

    // MARK: Data

    /// Compress arbitrary bytes into an xz stream.
    public static func compress(_ data: Data) throws -> Data {
        var stream = lzma_stream()
        let initResult = lzma_easy_encoder(
            &stream, defaultPreset, LZMA_CHECK_CRC64)
        guard initResult == LZMA_OK else {
            throw XzKitError.compressionFailed(
                "lzma_easy_encoder returned \(initResult.rawValue)")
        }
        defer { lzma_end(&stream) }
        return try driveStream(
            &stream, input: data, finishAction: LZMA_FINISH,
            errorMap: XzKitError.compressionFailed)
    }

    /// Decompress an xz / lzma1 stream back to its raw bytes.
    public static func decompress(_ data: Data) throws -> Data {
        var stream = lzma_stream()
        // memlimit = UINT64_MAX (no cap); flags = LZMA_CONCATENATED so
        // multi-stream files (`xz -F xz` default) decode end-to-end.
        // The macro expands to `UINT32_C(0x08)` which Swift's importer
        // doesn't surface — inline the literal.
        let lzmaConcatenated: UInt32 = 0x08
        let initResult = lzma_stream_decoder(
            &stream, UInt64.max, lzmaConcatenated)
        guard initResult == LZMA_OK else {
            throw XzKitError.decompressionFailed(
                "lzma_stream_decoder returned \(initResult.rawValue)")
        }
        defer { lzma_end(&stream) }
        return try driveStream(
            &stream, input: data, finishAction: LZMA_FINISH,
            errorMap: XzKitError.decompressionFailed)
    }

    /// Drives the lzma stream loop end-to-end, used for both encode
    /// and decode (only the init / error mapping differ).
    private static func driveStream(
        _ stream: inout lzma_stream,
        input data: Data,
        finishAction: lzma_action,
        errorMap: (String) -> XzKitError
    ) throws -> Data {
        var output = Data()
        var inputBytes = [UInt8](data)
        let inputCount = inputBytes.count
        var outputBuffer = [UInt8](repeating: 0, count: chunkSize)

        try inputBytes.withUnsafeMutableBufferPointer { inPtr in
            stream.next_in = UnsafePointer(inPtr.baseAddress)
            stream.avail_in = inputCount

            var done = false
            while !done {
                try outputBuffer.withUnsafeMutableBufferPointer { outPtr in
                    stream.next_out = outPtr.baseAddress
                    stream.avail_out = chunkSize
                    let r = lzma_code(&stream, finishAction)
                    let written = chunkSize - stream.avail_out
                    if written > 0 {
                        output.append(outPtr.baseAddress!, count: written)
                    }
                    switch r {
                    case LZMA_STREAM_END:
                        done = true
                    case LZMA_OK:
                        // No progress with no remaining input → truncated.
                        if written == 0 && stream.avail_in == 0 {
                            throw errorMap("incomplete xz stream (truncated input)")
                        }
                    default:
                        throw errorMap("lzma_code returned \(r.rawValue)")
                    }
                }
            }
        }
        return output
    }

    // MARK: Files

    /// Compress `source` into a `.xz` file. Default destination is
    /// `source.xz`.
    @discardableResult
    public static func compressFile(
        at source: URL,
        to destination: URL? = nil,
        keepInput: Bool = false,
        overwrite: Bool = false
    ) throws -> URL {
        let target = destination ?? URL(fileURLWithPath: source.path + ".xz")
        if FileManager.default.fileExists(atPath: target.path) && !overwrite {
            throw XzKitError.compressionFailed(
                "'\(target.path)' already exists; pass overwrite: true to replace")
        }
        let bytes = try Data(contentsOf: source)
        let compressed = try compress(bytes)
        try compressed.write(to: target)
        if !keepInput { try? FileManager.default.removeItem(at: source) }
        return target
    }

    /// Decompress an `.xz` file. Strips `.xz` (or `.txz` → `.tar`,
    /// `.lzma` → bare) when no destination is given.
    @discardableResult
    public static func decompressFile(
        at source: URL,
        to destination: URL? = nil,
        keepInput: Bool = false,
        overwrite: Bool = false
    ) throws -> URL {
        let target: URL
        if let destination {
            target = destination
        } else {
            target = try inferDecompressedName(from: source)
        }
        if FileManager.default.fileExists(atPath: target.path) && !overwrite {
            throw XzKitError.decompressionFailed(
                "'\(target.path)' already exists; pass overwrite: true to replace")
        }
        let bytes = try Data(contentsOf: source)
        let decompressed = try decompress(bytes)
        try decompressed.write(to: target)
        if !keepInput { try? FileManager.default.removeItem(at: source) }
        return target
    }

    private static func inferDecompressedName(from source: URL) throws -> URL {
        let path = source.path
        if path.hasSuffix(".xz") {
            return URL(fileURLWithPath: String(path.dropLast(3)))
        }
        if path.hasSuffix(".lzma") {
            return URL(fileURLWithPath: String(path.dropLast(5)))
        }
        if path.hasSuffix(".txz") {
            return URL(fileURLWithPath: String(path.dropLast(4)) + ".tar")
        }
        throw XzKitError.cannotInferOutputName(source)
    }
}

#endif // platform gate
