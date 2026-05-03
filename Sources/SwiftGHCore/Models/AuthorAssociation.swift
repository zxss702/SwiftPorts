import Foundation

/// `author_association` field on issues / PRs / comments.
public enum AuthorAssociation: String, Codable, Sendable {
    case collaborator = "COLLABORATOR"
    case contributor = "CONTRIBUTOR"
    case firstTimer = "FIRST_TIMER"
    case firstTimeContributor = "FIRST_TIME_CONTRIBUTOR"
    case mannequin = "MANNEQUIN"
    case member = "MEMBER"
    case none = "NONE"
    case owner = "OWNER"
}
