import Foundation

public enum ZstdKitError: Error, LocalizedError, Sendable, Equatable {
    case compressionFailed(String)
    case decompressionFailed(String)
    case cannotInferOutputName(URL)

    public var errorDescription: String? {
        switch self {
        case .compressionFailed(let m):
            return "zstd: compression failed: \(m)"
        case .decompressionFailed(let m):
            return "zstd: decompression failed: \(m)"
        case .cannotInferOutputName(let u):
            return "zstd: cannot infer output name from '\(u.path)' (no .zst/.tzst suffix)"
        }
    }
}
