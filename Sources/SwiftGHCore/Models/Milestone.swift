import Foundation

public struct Milestone: Codable, Sendable, Identifiable {
    public let id: Int
    public let nodeId: String
    public let number: Int
    public let title: String
    public let description: String?
    public let state: IssueState
    public let creator: User?
    public let openIssues: Int
    public let closedIssues: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let dueOn: Date?
    public let closedAt: Date?
    public let htmlUrl: URL
    public let url: URL
}
