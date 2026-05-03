import Foundation

/// Body for `PUT /repos/{o}/{r}/pulls/{n}/merge`.
public struct PullRequestMergeRequest: Codable, Sendable {
    public var commitTitle: String?
    public var commitMessage: String?
    public var sha: String?
    public var mergeMethod: MergeMethod?

    public enum MergeMethod: String, Codable, Sendable {
        case merge, squash, rebase
    }

    public init(
        commitTitle: String? = nil,
        commitMessage: String? = nil,
        sha: String? = nil,
        mergeMethod: MergeMethod? = nil
    ) {
        self.commitTitle = commitTitle
        self.commitMessage = commitMessage
        self.sha = sha
        self.mergeMethod = mergeMethod
    }
}

public struct PullRequestMergeResponse: Codable, Sendable {
    public let sha: String
    public let merged: Bool
    public let message: String?
}
