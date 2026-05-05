import Foundation

/// GraphQL queries that mirror upstream `gh`'s read paths for
/// repository-scoped collections (labels, PRs, issues, releases, repo
/// view, etc). Used to feed `--json` field-selector output where REST
/// can't supply the same fields (createdAt/updatedAt on labels, full
/// PR author/labels/reviews graph, etc).
public enum RepositoryQueries {

    // MARK: Labels

    public static let repositoryLabels = """
        query($owner: String!, $name: String!, $first: Int!) {
          repository(owner: $owner, name: $name) {
            labels(first: $first) {
              totalCount
              nodes {
                id, name, color, description, isDefault,
                createdAt, updatedAt, url
              }
            }
          }
        }
        """
}

// MARK: Response envelopes & nodes

public struct RepositoryLabelsResponse: Codable, Sendable {
    public let repository: LabelContainer?
    public struct LabelContainer: Codable, Sendable {
        public let labels: LabelConnection
    }
}

public struct LabelConnection: Codable, Sendable {
    public let totalCount: Int
    public let nodes: [GraphQLLabel]
}

public struct GraphQLLabel: Codable, Sendable {
    public let id: String
    public let name: String
    public let color: String
    public let description: String?
    public let isDefault: Bool
    public let createdAt: Date?
    public let updatedAt: Date?
    public let url: URL
}
