import Foundation

/// One GitLab release. The `tag_name` is the primary identity; an
/// associated `description` (markdown) is the body, and zero-or-more
/// `assets.links` carry downloadable attachments.
public struct Release: Codable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    public let description: String?
    public let createdAt: Date
    public let releasedAt: Date?
    public let author: User?
    public let assets: Assets?
    public let _links: Links?

    public struct Assets: Codable, Sendable, Equatable {
        public let count: Int
        public let sources: [Source]?
        public let links: [Link]?

        public struct Source: Codable, Sendable, Equatable {
            public let format: String
            public let url: URL
        }
        public struct Link: Codable, Sendable, Equatable {
            public let id: Int
            public let name: String
            public let url: URL
            public let linkType: String?
        }
    }

    public struct Links: Codable, Sendable, Equatable {
        public let selfLink: URL?

        enum CodingKeys: String, CodingKey {
            case selfLink = "self"
        }
    }
}
