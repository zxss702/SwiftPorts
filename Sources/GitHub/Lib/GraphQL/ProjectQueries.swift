import Foundation

/// Canonical GraphQL queries for ProjectV2. Defined as constants so
/// commands stay readable and the queries are easy to grep / share.
public enum ProjectQueries {

    // MARK: List

    /// `viewer { projectsV2 }` — your own projects.
    public static let viewerProjects = """
        query($first: Int!) {
          viewer {
            projectsV2(first: $first, orderBy: {field: UPDATED_AT, direction: DESC}) {
              totalCount
              nodes {
                id, number, title, shortDescription, url,
                closed, public, readme, createdAt, updatedAt,
                owner { __typename ... on User { login } ... on Organization { login } },
                fields(first: 0) { totalCount },
                items(first: 0) { totalCount }
              }
            }
          }
        }
        """

    /// `user(login:) { projectsV2 }` — projects owned by a user.
    public static let userProjects = """
        query($login: String!, $first: Int!) {
          user(login: $login) {
            projectsV2(first: $first, orderBy: {field: UPDATED_AT, direction: DESC}) {
              totalCount
              nodes {
                id, number, title, shortDescription, url,
                closed, public, readme, createdAt, updatedAt,
                owner { __typename ... on User { login } ... on Organization { login } },
                fields(first: 0) { totalCount },
                items(first: 0) { totalCount }
              }
            }
          }
        }
        """

    /// `organization(login:) { projectsV2 }` — projects owned by an org.
    public static let orgProjects = """
        query($login: String!, $first: Int!) {
          organization(login: $login) {
            projectsV2(first: $first, orderBy: {field: UPDATED_AT, direction: DESC}) {
              totalCount
              nodes {
                id, number, title, shortDescription, url,
                closed, public, readme, createdAt, updatedAt,
                owner { __typename ... on User { login } ... on Organization { login } },
                fields(first: 0) { totalCount },
                items(first: 0) { totalCount }
              }
            }
          }
        }
        """

    // MARK: View

    public static let viewerProject = """
        query($number: Int!) {
          viewer {
            projectV2(number: $number) {
              id, number, title, shortDescription, url,
              closed, public, readme, createdAt, updatedAt,
              owner { __typename ... on User { login } ... on Organization { login } },
              fields(first: 0) { totalCount },
              items(first: 0) { totalCount }
            }
          }
        }
        """

    public static let userProject = """
        query($login: String!, $number: Int!) {
          user(login: $login) {
            projectV2(number: $number) {
              id, number, title, shortDescription, url,
              closed, public, readme, createdAt, updatedAt,
              owner { __typename ... on User { login } ... on Organization { login } },
              fields(first: 0) { totalCount },
              items(first: 0) { totalCount }
            }
          }
        }
        """

    public static let orgProject = """
        query($login: String!, $number: Int!) {
          organization(login: $login) {
            projectV2(number: $number) {
              id, number, title, shortDescription, url,
              closed, public, readme, createdAt, updatedAt,
              owner { __typename ... on User { login } ... on Organization { login } },
              fields(first: 0) { totalCount },
              items(first: 0) { totalCount }
            }
          }
        }
        """

    // MARK: Items

    public static let viewerProjectItems = """
        query($number: Int!, $first: Int!) {
          viewer {
            projectV2(number: $number) {
              items(first: $first) {
                totalCount
                nodes {
                  id, type, createdAt, updatedAt,
                  content {
                    __typename
                    ... on Issue { number, title, state, url }
                    ... on PullRequest { number, title, state, url }
                    ... on DraftIssue { title, body }
                  }
                }
              }
            }
          }
        }
        """

    public static let userProjectItems = """
        query($login: String!, $number: Int!, $first: Int!) {
          user(login: $login) {
            projectV2(number: $number) {
              items(first: $first) {
                totalCount
                nodes {
                  id, type, createdAt, updatedAt,
                  content {
                    __typename
                    ... on Issue { number, title, state, url }
                    ... on PullRequest { number, title, state, url }
                    ... on DraftIssue { title, body }
                  }
                }
              }
            }
          }
        }
        """

    public static let orgProjectItems = """
        query($login: String!, $number: Int!, $first: Int!) {
          organization(login: $login) {
            projectV2(number: $number) {
              items(first: $first) {
                totalCount
                nodes {
                  id, type, createdAt, updatedAt,
                  content {
                    __typename
                    ... on Issue { number, title, state, url }
                    ... on PullRequest { number, title, state, url }
                    ... on DraftIssue { title, body }
                  }
                }
              }
            }
          }
        }
        """
}

// MARK: Response envelopes

public struct ViewerProjectsResponse: Codable, Sendable {
    public let viewer: ViewerProjectsContainer
    public struct ViewerProjectsContainer: Codable, Sendable {
        public let projectsV2: ProjectV2Connection
    }
}

public struct UserProjectsResponse: Codable, Sendable {
    public let user: UserContainer?
    public struct UserContainer: Codable, Sendable {
        public let projectsV2: ProjectV2Connection
    }
}

public struct OrgProjectsResponse: Codable, Sendable {
    public let organization: OrgContainer?
    public struct OrgContainer: Codable, Sendable {
        public let projectsV2: ProjectV2Connection
    }
}

public struct ViewerProjectResponse: Codable, Sendable {
    public let viewer: ViewerProjectContainer
    public struct ViewerProjectContainer: Codable, Sendable {
        public let projectV2: ProjectV2WithItemCount?
    }
}

public struct UserProjectResponse: Codable, Sendable {
    public let user: UserContainer?
    public struct UserContainer: Codable, Sendable {
        public let projectV2: ProjectV2WithItemCount?
    }
}

public struct OrgProjectResponse: Codable, Sendable {
    public let organization: OrgContainer?
    public struct OrgContainer: Codable, Sendable {
        public let projectV2: ProjectV2WithItemCount?
    }
}

/// Project plus item count — used by `view` so the user gets a sense
/// of size without having to also list items.
public struct ProjectV2WithItemCount: Codable, Sendable, Identifiable {
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
    public let items: ProjectV2CountContainer
}

public struct ViewerProjectItemsResponse: Codable, Sendable {
    public let viewer: ViewerContainer
    public struct ViewerContainer: Codable, Sendable {
        public let projectV2: ProjectV2ItemsContainer?
    }
}

public struct UserProjectItemsResponse: Codable, Sendable {
    public let user: UserContainer?
    public struct UserContainer: Codable, Sendable {
        public let projectV2: ProjectV2ItemsContainer?
    }
}

public struct OrgProjectItemsResponse: Codable, Sendable {
    public let organization: OrgContainer?
    public struct OrgContainer: Codable, Sendable {
        public let projectV2: ProjectV2ItemsContainer?
    }
}

public struct ProjectV2ItemsContainer: Codable, Sendable {
    public let items: ProjectV2ItemConnection
}

public struct ProjectV2ItemConnection: Codable, Sendable {
    public let totalCount: Int
    public let nodes: [ProjectV2Item]
}
