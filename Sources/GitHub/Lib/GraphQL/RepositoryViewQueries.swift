import Foundation

/// GraphQL queries for `gh repo list/view --json`. Repos have ~70
/// upstream-exposed fields; we fetch a comprehensive subset covering
/// every commonly-used name. Heavy paged collections
/// (assignableUsers, mentionableUsers, milestones, issueTemplates)
/// require an extra round trip per field and are returned empty
/// by the field map for now.
public enum RepositoryViewQueries {

    private static let fields = """
        id
        name
        nameWithOwner
        owner { __typename id login }
        description
        url
        sshUrl
        homepageUrl
        mirrorUrl
        isPrivate
        isFork
        isArchived
        isTemplate
        isEmpty
        isMirror
        isInOrganization
        isBlankIssuesEnabled
        isSecurityPolicyEnabled
        isUserConfigurationRepository
        usesCustomOpenGraphImage
        openGraphImageUrl
        securityPolicyUrl
        hasIssuesEnabled
        hasProjectsEnabled
        hasWikiEnabled
        hasDiscussionsEnabled
        defaultBranchRef { name }
        primaryLanguage { name }
        languages(first: 100) {
          totalSize
          edges { size node { name id } }
        }
        repositoryTopics(first: 100) {
          nodes { topic { name } }
        }
        stargazerCount
        forkCount
        watchers { totalCount }
        diskUsage
        createdAt
        updatedAt
        pushedAt
        archivedAt
        pullRequests { totalCount }
        issues { totalCount }
        licenseInfo { key name nickname spdxId url }
        mergeCommitAllowed
        squashMergeAllowed
        rebaseMergeAllowed
        deleteBranchOnMerge
        parent {
          id name nameWithOwner
          owner { __typename id login }
          isPrivate
          url
        }
        templateRepository {
          id name nameWithOwner
          owner { __typename id login }
          isPrivate
          url
        }
        latestRelease {
          tagName name url isDraft isPrerelease publishedAt createdAt
        }
        viewerCanAdminister
        viewerDefaultCommitEmail
        viewerDefaultMergeMethod
        viewerHasStarred
        viewerPermission
        viewerSubscription
        visibility
        """

    public static let view = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            \(fields)
          }
        }
        """

    /// Repos owned by the authenticated user, or by another `owner`.
    public static let viewerRepos = """
        query($first: Int!) {
          viewer {
            repositories(
              first: $first,
              orderBy: {field: PUSHED_AT, direction: DESC},
              ownerAffiliations: [OWNER]
            ) {
              totalCount
              nodes {
                \(fields)
              }
            }
          }
        }
        """

    public static let userRepos = """
        query($login: String!, $first: Int!) {
          user(login: $login) {
            repositories(
              first: $first,
              orderBy: {field: PUSHED_AT, direction: DESC},
              ownerAffiliations: [OWNER]
            ) {
              totalCount
              nodes {
                \(fields)
              }
            }
          }
        }
        """

    public static let orgRepos = """
        query($login: String!, $first: Int!) {
          organization(login: $login) {
            repositories(
              first: $first,
              orderBy: {field: PUSHED_AT, direction: DESC}
            ) {
              totalCount
              nodes {
                \(fields)
              }
            }
          }
        }
        """
}

public struct RepositoryViewResponse: Codable, Sendable {
    public let repository: GraphQLRepository?
}

public struct ViewerReposResponse: Codable, Sendable {
    public let viewer: ViewerContainer
    public struct ViewerContainer: Codable, Sendable {
        public let repositories: RepoConnection
    }
}

public struct UserReposResponse: Codable, Sendable {
    public let user: UserContainer?
    public struct UserContainer: Codable, Sendable {
        public let repositories: RepoConnection
    }
}

public struct OrgReposResponse: Codable, Sendable {
    public let organization: OrgContainer?
    public struct OrgContainer: Codable, Sendable {
        public let repositories: RepoConnection
    }
}

public struct RepoConnection: Codable, Sendable {
    public let totalCount: Int
    public let nodes: [GraphQLRepository]
}

public struct GraphQLRepository: Codable, Sendable {
    public let id: String
    public let name: String
    public let nameWithOwner: String
    public let owner: GQLOwner?
    public let description: String?
    public let url: URL
    public let sshUrl: String
    public let homepageUrl: URL?
    public let mirrorUrl: URL?
    public let isPrivate: Bool
    public let isFork: Bool
    public let isArchived: Bool
    public let isTemplate: Bool
    public let isEmpty: Bool
    public let isMirror: Bool
    public let isInOrganization: Bool
    public let isBlankIssuesEnabled: Bool
    public let isSecurityPolicyEnabled: Bool?
    public let isUserConfigurationRepository: Bool
    public let usesCustomOpenGraphImage: Bool
    public let openGraphImageUrl: URL?
    public let securityPolicyUrl: URL?
    public let hasIssuesEnabled: Bool
    public let hasProjectsEnabled: Bool
    public let hasWikiEnabled: Bool
    public let hasDiscussionsEnabled: Bool
    public let defaultBranchRef: GQLNamed?
    public let primaryLanguage: GQLNamed?
    public let languages: GQLLanguageConnection?
    public let repositoryTopics: GQLNodeList<GQLTopicWrap>?
    public let stargazerCount: Int
    public let forkCount: Int
    public let watchers: GQLCount?
    public let diskUsage: Int?
    public let createdAt: Date
    public let updatedAt: Date
    public let pushedAt: Date?
    public let archivedAt: Date?
    public let pullRequests: GQLCount?
    public let issues: GQLCount?
    public let licenseInfo: GQLLicenseInfo?
    public let mergeCommitAllowed: Bool
    public let squashMergeAllowed: Bool
    public let rebaseMergeAllowed: Bool
    public let deleteBranchOnMerge: Bool
    public let parent: GQLRepoParent?
    public let templateRepository: GQLRepoParent?
    public let latestRelease: GQLLatestRelease?
    public let viewerCanAdminister: Bool
    public let viewerDefaultCommitEmail: String?
    public let viewerDefaultMergeMethod: String?
    public let viewerHasStarred: Bool
    public let viewerPermission: String?
    public let viewerSubscription: String?
    public let visibility: String
}

public struct GQLNamed: Codable, Sendable {
    public let name: String
    public let id: String?
}

public struct GQLLanguageConnection: Codable, Sendable {
    public let totalSize: Int
    public let edges: [GQLLanguageEdge]
}

public struct GQLLanguageEdge: Codable, Sendable {
    public let size: Int
    public let node: GQLNamed
}

public struct GQLTopicWrap: Codable, Sendable {
    public let topic: GQLNamed
}

public struct GQLLicenseInfo: Codable, Sendable {
    public let key: String
    public let name: String
    public let nickname: String?
    public let spdxId: String?
    public let url: URL?
}

public struct GQLRepoParent: Codable, Sendable {
    public let id: String
    public let name: String
    public let nameWithOwner: String
    public let owner: GQLOwner?
    public let isPrivate: Bool
    public let url: URL
}

public struct GQLLatestRelease: Codable, Sendable {
    public let tagName: String
    public let name: String?
    public let url: URL
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let publishedAt: Date?
    public let createdAt: Date
}
