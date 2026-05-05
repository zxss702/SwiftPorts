import Foundation

/// `ProjectV2` (the new-style GitHub Projects). Strictly GraphQL — no
/// REST equivalent.
public struct ProjectV2: Codable, Sendable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    public let shortDescription: String?
    public let url: URL
    public let closed: Bool
    public let `public`: Bool
    public let readme: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let owner: ProjectV2Owner?
    public let fields: ProjectV2CountContainer?
    public let items: ProjectV2CountContainer?
}

/// `ProjectV2Connection.nodes` envelope shape.
public struct ProjectV2Connection: Codable, Sendable {
    public let nodes: [ProjectV2]
    public let totalCount: Int?
}

/// Owner sub-object on `ProjectV2`. The GraphQL `owner` interface
/// covers `User` and `Organization`; we surface `__typename` as
/// `type` to match upstream gh's JSON shape (`{login, type}`).
public struct ProjectV2Owner: Codable, Sendable {
    public let login: String
    public let type: String

    enum CodingKeys: String, CodingKey {
        case login
        case type = "__typename"
    }
}

/// `{ totalCount }` envelope used for `fields` and `items` connections.
public struct ProjectV2CountContainer: Codable, Sendable {
    public let totalCount: Int
}
