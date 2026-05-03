import Foundation

/// Body for `POST /repos/{o}/{r}/pulls`.
public struct PullRequestCreateRequest: Codable, Sendable {
    public var title: String
    public var head: String
    public var base: String
    public var body: String?
    public var draft: Bool?
    public var maintainerCanModify: Bool?

    public init(
        title: String,
        head: String,
        base: String,
        body: String? = nil,
        draft: Bool? = nil,
        maintainerCanModify: Bool? = nil
    ) {
        self.title = title
        self.head = head
        self.base = base
        self.body = body
        self.draft = draft
        self.maintainerCanModify = maintainerCanModify
    }
}
