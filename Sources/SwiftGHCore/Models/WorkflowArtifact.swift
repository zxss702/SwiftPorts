import Foundation

/// `GET /repos/{o}/{r}/actions/runs/{id}/artifacts` envelope.
public struct WorkflowArtifactList: Codable, Sendable {
    public let totalCount: Int
    public let artifacts: [WorkflowArtifact]
}

public struct WorkflowArtifact: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let name: String
    public let sizeInBytes: Int64
    public let url: URL
    public let archiveDownloadUrl: URL
    public let expired: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    public let expiresAt: Date?
    public let workflowRun: WorkflowRunRef?
}

public struct WorkflowRunRef: Codable, Sendable {
    public let id: Int
    public let repositoryId: Int?
    public let headBranch: String?
    public let headSha: String?
}
