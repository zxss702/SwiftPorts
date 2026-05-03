import Foundation

public struct ReleaseAsset: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let name: String
    public let label: String?
    public let contentType: String
    public let state: String
    public let size: Int64
    public let downloadCount: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let url: URL
    public let browserDownloadUrl: URL
    public let uploader: User?
    public let digest: String?
}
