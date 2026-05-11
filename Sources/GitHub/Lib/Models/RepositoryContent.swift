import Foundation

/// Response payload from `GET /repos/{owner}/{repo}/readme` and the
/// general contents API. Files arrive base64-encoded; the helper
/// `decodedContent()` does the decode in one place so call sites
/// stay tidy.
public struct RepositoryContent: Codable, Sendable {
    public let name: String
    public let path: String
    public let size: Int
    public let encoding: String?
    /// Base64-encoded payload (when `encoding == "base64"`). GitHub
    /// wraps the base64 output to 60-character lines, so callers
    /// must strip whitespace before decoding.
    public let content: String?
    public let downloadUrl: URL?
    public let htmlUrl: URL?

    /// Decode `content` into a UTF-8 `String`. Returns nil when the
    /// payload is missing, the encoding isn't base64, or the bytes
    /// aren't valid UTF-8.
    public func decodedContent() -> String? {
        guard let content,
              encoding == "base64" else { return nil }
        let stripped = content.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: stripped) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
