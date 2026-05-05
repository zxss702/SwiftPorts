import Foundation

public enum Bzip2KitError: Error, LocalizedError, Sendable, Equatable {
    case compressionFailed(String)
    case decompressionFailed(String)
    case cannotInferOutputName(URL)

    public var errorDescription: String? {
        switch self {
        case .compressionFailed(let m):
            return "bzip2: compression failed: \(m)"
        case .decompressionFailed(let m):
            return "bzip2: decompression failed: \(m)"
        case .cannotInferOutputName(let u):
            return "bzip2: cannot infer output name from '\(u.path)' (no .bz2/.tbz/.tbz2 suffix)"
        }
    }
}
