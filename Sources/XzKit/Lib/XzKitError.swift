import Foundation

public enum XzKitError: Error, LocalizedError, Sendable, Equatable {
    case compressionFailed(String)
    case decompressionFailed(String)
    case cannotInferOutputName(URL)

    public var errorDescription: String? {
        switch self {
        case .compressionFailed(let m):
            return "xz: compression failed: \(m)"
        case .decompressionFailed(let m):
            return "xz: decompression failed: \(m)"
        case .cannotInferOutputName(let u):
            return "xz: cannot infer output name from '\(u.path)' (no .xz/.lzma/.txz suffix)"
        }
    }
}
