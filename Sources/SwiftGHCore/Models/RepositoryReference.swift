import Foundation

/// `owner/name` repo reference. Used as a value type in CLI argv
/// parsing and to construct REST paths.
public struct RepositoryReference: Sendable, Hashable, Codable {
    public let owner: String
    public let name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Parse an `owner/name` (or `host/owner/name`) string.
    public init(parsing input: String) throws {
        let parts = input.split(separator: "/")
        switch parts.count {
        case 2:
            self.owner = String(parts[0])
            self.name = String(parts[1])
        case 3:
            self.owner = String(parts[1])
            self.name = String(parts[2])
        default:
            throw RepositoryReferenceParseError.malformed(input)
        }
        guard !owner.isEmpty, !name.isEmpty else {
            throw RepositoryReferenceParseError.malformed(input)
        }
    }

    public var slug: String { "\(owner)/\(name)" }
}

public enum RepositoryReferenceParseError: Error, LocalizedError, Sendable {
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let s):
            return "Expected OWNER/NAME, got \"\(s)\"."
        }
    }
}
