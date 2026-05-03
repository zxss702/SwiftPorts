import Foundation

/// GitLab project issue board (kanban). The `lists` array holds the
/// non-default columns; the implicit "Open" / "Closed" columns aren't
/// included in `lists`.
public struct Board: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let projectId: Int?
    public let groupId: Int?
    public let milestone: Milestone?
    public let assignee: User?
    public let labels: [BoardLabel]?
    public let weight: Int?
    public let lists: [BoardList]?
    public let hideBacklogList: Bool?
    public let hideClosedList: Bool?

    public struct BoardLabel: Codable, Sendable {
        public let id: Int?
        public let name: String
        public let color: String?
        public let textColor: String?
        public let description: String?
    }
}

/// One column of an issue board.
public struct BoardList: Codable, Sendable, Identifiable {
    public let id: Int
    public let label: BoardListLabel?
    public let position: Int?
    public let maxIssueCount: Int?
    public let maxIssueWeight: Int?
    public let limitMetric: String?

    public struct BoardListLabel: Codable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let description: String?
        public let color: String?
        public let textColor: String?
    }
}
