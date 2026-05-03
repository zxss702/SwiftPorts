import Foundation

/// `GET /search/{kind}` envelope.
public struct SearchResult<Item: Codable & Sendable>: Codable, Sendable {
    public let totalCount: Int
    public let incompleteResults: Bool
    public let items: [Item]
}
