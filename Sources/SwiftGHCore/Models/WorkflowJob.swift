import Foundation

/// `GET /repos/{o}/{r}/actions/jobs/{id}` and the elements of
/// `GET /repos/{o}/{r}/actions/runs/{id}/jobs`.
public struct WorkflowJob: Codable, Sendable, Identifiable {
    public let id: Int
    public let runId: Int
    public let runUrl: URL
    public let nodeId: String
    public let headSha: String
    public let url: URL
    public let htmlUrl: URL?
    public let status: String              // queued / in_progress / completed / waiting
    public let conclusion: String?         // success / failure / cancelled / skipped / …
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    public let name: String
    public let steps: [WorkflowJobStep]?
    public let labels: [String]?
    public let runnerName: String?
    public let workflowName: String?
    public let headBranch: String?
}

public struct WorkflowJobStep: Codable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let number: Int
    public let startedAt: Date?
    public let completedAt: Date?
}

/// `GET /repos/{o}/{r}/actions/runs/{id}/jobs` envelope.
public struct WorkflowJobList: Codable, Sendable {
    public let totalCount: Int
    public let jobs: [WorkflowJob]
}
