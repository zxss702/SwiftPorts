import Foundation

/// Response payload from `GET /projects/:id/repository/files/:file`.
/// The `content` field is base64-encoded; `decodedContent()`
/// centralizes the decode so callers don't repeat the dance.
public struct RepositoryFile: Codable, Sendable {
    public let fileName: String
    public let filePath: String
    public let size: Int
    public let encoding: String
    public let contentSha256: String?
    public let ref: String
    public let blobId: String?
    public let commitId: String?
    public let lastCommitId: String?
    public let content: String

    /// Decode `content` into a UTF-8 `String`. Returns nil when
    /// the encoding isn't base64 or the bytes aren't valid UTF-8.
    public func decodedContent() -> String? {
        guard encoding == "base64" else { return nil }
        let stripped = content.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: stripped) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    enum CodingKeys: String, CodingKey {
        case fileName       = "file_name"
        case filePath       = "file_path"
        case size, encoding
        case contentSha256  = "content_sha256"
        case ref
        case blobId         = "blob_id"
        case commitId       = "commit_id"
        case lastCommitId   = "last_commit_id"
        case content
    }
}
