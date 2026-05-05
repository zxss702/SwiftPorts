import Foundation

/// Element of `GET /search/commits`.
public struct CommitSearchItem: Codable, Sendable, Identifiable {
    public let sha: String
    public let url: URL
    public let htmlUrl: URL
    public let commit: CommitDetail
    public let author: User?
    public let committer: User?
    public let repository: MinimalRepository
    public let score: Double?

    public var id: String { sha }
}

public struct CommitDetail: Codable, Sendable {
    public let message: String
    public let author: CommitSignature
    public let committer: CommitSignature
    public let tree: GitTreeRef?
    public let commentCount: Int?
}

public struct GitTreeRef: Codable, Sendable {
    public let sha: String
    public let url: URL?
}

public struct CommitSignature: Codable, Sendable {
    public let name: String
    public let email: String
    public let date: Date
}
