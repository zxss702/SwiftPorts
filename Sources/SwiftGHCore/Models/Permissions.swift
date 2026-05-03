import Foundation

/// Repository-level permissions for the authenticated user.
/// Absent for unauthenticated requests against public repos.
public struct Permissions: Codable, Sendable {
    public let admin: Bool
    public let maintain: Bool?
    public let push: Bool
    public let triage: Bool?
    public let pull: Bool
}
