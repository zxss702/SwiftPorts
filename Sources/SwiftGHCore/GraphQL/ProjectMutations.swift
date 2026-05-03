import Foundation

/// Canonical GraphQL mutations for ProjectV2.
///
/// All ProjectV2 mutations target node IDs (opaque strings), not the
/// human-friendly project number. Commands first run a small lookup
/// query to translate `--owner`/`--number` (or an item URL) into the
/// IDs the mutation needs, then submit the mutation.
public enum ProjectMutations {

    // MARK: Project lifecycle

    public static let createProject = """
        mutation($ownerId: ID!, $title: String!) {
          createProjectV2(input: {ownerId: $ownerId, title: $title}) {
            projectV2 {
              id, number, title, url, createdAt, updatedAt, public, closed
            }
          }
        }
        """

    public static let updateProject = """
        mutation($id: ID!, $title: String, $shortDescription: String, $readme: String, $public: Boolean, $closed: Boolean) {
          updateProjectV2(input: {projectId: $id, title: $title, shortDescription: $shortDescription, readme: $readme, public: $public, closed: $closed}) {
            projectV2 {
              id, number, title, shortDescription, readme, url, public, closed, createdAt, updatedAt
            }
          }
        }
        """

    public static let deleteProject = """
        mutation($id: ID!) {
          deleteProjectV2(input: {projectId: $id}) {
            projectV2 { id }
          }
        }
        """

    // MARK: Items

    public static let addProjectItemById = """
        mutation($projectId: ID!, $contentId: ID!) {
          addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
            item { id, type }
          }
        }
        """

    public static let addProjectDraftIssue = """
        mutation($projectId: ID!, $title: String!, $body: String) {
          addProjectV2DraftIssue(input: {projectId: $projectId, title: $title, body: $body}) {
            projectItem { id, type }
          }
        }
        """

    public static let archiveProjectItem = """
        mutation($projectId: ID!, $itemId: ID!) {
          archiveProjectV2Item(input: {projectId: $projectId, itemId: $itemId}) {
            item { id }
          }
        }
        """

    public static let unarchiveProjectItem = """
        mutation($projectId: ID!, $itemId: ID!) {
          unarchiveProjectV2Item(input: {projectId: $projectId, itemId: $itemId}) {
            item { id }
          }
        }
        """

    public static let deleteProjectItem = """
        mutation($projectId: ID!, $itemId: ID!) {
          deleteProjectV2Item(input: {projectId: $projectId, itemId: $itemId}) {
            deletedItemId
          }
        }
        """

    public static let copyProject = """
        mutation($projectId: ID!, $targetOwnerId: ID!, $title: String!, $includeDraftIssues: Boolean) {
          copyProjectV2(input: {projectId: $projectId, ownerId: $targetOwnerId, title: $title, includeDraftIssues: $includeDraftIssues}) {
            projectV2 {
              id, number, title, shortDescription, readme, url, public, closed, createdAt, updatedAt
            }
          }
        }
        """

    public static let markProjectAsTemplate = """
        mutation($projectId: ID!) {
          markProjectV2AsTemplate(input: {projectId: $projectId}) {
            projectV2 { id, template }
          }
        }
        """

    public static let unmarkProjectAsTemplate = """
        mutation($projectId: ID!) {
          unmarkProjectV2AsTemplate(input: {projectId: $projectId}) {
            projectV2 { id, template }
          }
        }
        """

    public static let linkProjectToRepository = """
        mutation($projectId: ID!, $repositoryId: ID!) {
          linkProjectV2ToRepository(input: {projectId: $projectId, repositoryId: $repositoryId}) {
            repository { nameWithOwner }
          }
        }
        """

    public static let unlinkProjectFromRepository = """
        mutation($projectId: ID!, $repositoryId: ID!) {
          unlinkProjectV2FromRepository(input: {projectId: $projectId, repositoryId: $repositoryId}) {
            repository { nameWithOwner }
          }
        }
        """

    public static let linkProjectToTeam = """
        mutation($projectId: ID!, $teamId: ID!) {
          linkProjectV2ToTeam(input: {projectId: $projectId, teamId: $teamId}) {
            team { name }
          }
        }
        """

    public static let unlinkProjectFromTeam = """
        mutation($projectId: ID!, $teamId: ID!) {
          unlinkProjectV2FromTeam(input: {projectId: $projectId, teamId: $teamId}) {
            team { name }
          }
        }
        """

    // MARK: Field create / delete

    public static let createField = """
        mutation($projectId: ID!, $name: String!, $dataType: ProjectV2CustomFieldType!, $options: [ProjectV2SingleSelectFieldOptionInput!]) {
          createProjectV2Field(input: {projectId: $projectId, name: $name, dataType: $dataType, singleSelectOptions: $options}) {
            projectV2Field {
              __typename
              ... on ProjectV2Field { id name dataType }
              ... on ProjectV2IterationField { id name dataType }
              ... on ProjectV2SingleSelectField {
                id name dataType
                options { id name }
              }
            }
          }
        }
        """

    public static let deleteField = """
        mutation($fieldId: ID!) {
          deleteProjectV2Field(input: {fieldId: $fieldId}) {
            projectV2Field {
              __typename
              ... on ProjectV2Field { id name dataType }
              ... on ProjectV2IterationField { id name dataType }
              ... on ProjectV2SingleSelectField { id name dataType }
            }
          }
        }
        """

    // MARK: Item field-value editing

    /// Discriminated by which `value` key is set; pass exactly one.
    public static let updateItemFieldValue = """
        mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: ProjectV2FieldValue!) {
          updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId, value: $value}) {
            projectV2Item { id }
          }
        }
        """

    /// Clear a value (text / number / date / select / iteration).
    public static let clearItemFieldValue = """
        mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!) {
          clearProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId}) {
            projectV2Item { id }
          }
        }
        """

    // MARK: Fields (read)

    public static let viewerProjectFields = """
        query($number: Int!, $first: Int!) {
          viewer {
            projectV2(number: $number) {
              fields(first: $first) {
                totalCount
                nodes {
                  __typename
                  ... on ProjectV2Field { id name dataType }
                  ... on ProjectV2IterationField { id name dataType }
                  ... on ProjectV2SingleSelectField {
                    id name dataType
                    options { id name }
                  }
                }
              }
            }
          }
        }
        """

    public static let userProjectFields = """
        query($login: String!, $number: Int!, $first: Int!) {
          user(login: $login) {
            projectV2(number: $number) {
              fields(first: $first) {
                totalCount
                nodes {
                  __typename
                  ... on ProjectV2Field { id name dataType }
                  ... on ProjectV2IterationField { id name dataType }
                  ... on ProjectV2SingleSelectField {
                    id name dataType
                    options { id name }
                  }
                }
              }
            }
          }
        }
        """

    public static let orgProjectFields = """
        query($login: String!, $number: Int!, $first: Int!) {
          organization(login: $login) {
            projectV2(number: $number) {
              fields(first: $first) {
                totalCount
                nodes {
                  __typename
                  ... on ProjectV2Field { id name dataType }
                  ... on ProjectV2IterationField { id name dataType }
                  ... on ProjectV2SingleSelectField {
                    id name dataType
                    options { id name }
                  }
                }
              }
            }
          }
        }
        """

    // MARK: ID lookups

    /// Resolve `viewer.id` (your user node ID).
    public static let viewerId = "query { viewer { id } }"

    /// Resolve `user(login:).id`.
    public static let userId = "query($login: String!) { user(login: $login) { id } }"

    /// Resolve `organization(login:).id`.
    public static let organizationId =
        "query($login: String!) { organization(login: $login) { id } }"

    /// Resolve any GitHub URL to a UniformResourceLocatable's id.
    /// Used by `gh project item-add --url ...` to translate an issue
    /// or PR URL into a contentId.
    public static let resourceId = """
        query($url: URI!) {
          resource(url: $url) {
            __typename
            ... on Issue { id }
            ... on PullRequest { id }
          }
        }
        """

    /// Resolve `repository(owner:, name:).id`.
    public static let repositoryId = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) { id }
        }
        """

    /// Resolve `organization.team(slug:).id`.
    public static let teamId = """
        query($org: String!, $slug: String!) {
          organization(login: $org) {
            team(slug: $slug) { id }
          }
        }
        """

    /// Resolve a project (viewer/user/org) to its node ID by number.
    public static let viewerProjectId = """
        query($number: Int!) {
          viewer { projectV2(number: $number) { id } }
        }
        """
    public static let userProjectId = """
        query($login: String!, $number: Int!) {
          user(login: $login) { projectV2(number: $number) { id } }
        }
        """
    public static let orgProjectId = """
        query($login: String!, $number: Int!) {
          organization(login: $login) { projectV2(number: $number) { id } }
        }
        """
}

// MARK: Response envelopes

public struct CreateProjectResponse: Codable, Sendable {
    public let createProjectV2: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2: ProjectV2
    }
}

public struct UpdateProjectResponse: Codable, Sendable {
    public let updateProjectV2: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2: ProjectV2
    }
}

public struct DeleteProjectResponse: Codable, Sendable {
    public let deleteProjectV2: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2: NodeID
    }
}

public struct NodeID: Codable, Sendable { public let id: String }

public struct AddProjectItemByIdResponse: Codable, Sendable {
    public let addProjectV2ItemById: Inner
    public struct Inner: Codable, Sendable {
        public let item: ProjectItemRef
    }
}

public struct AddProjectDraftIssueResponse: Codable, Sendable {
    public let addProjectV2DraftIssue: Inner
    public struct Inner: Codable, Sendable {
        public let projectItem: ProjectItemRef
    }
}

public struct ArchiveProjectItemResponse: Codable, Sendable {
    public let archiveProjectV2Item: Inner
    public struct Inner: Codable, Sendable {
        public let item: NodeID
    }
}

public struct UnarchiveProjectItemResponse: Codable, Sendable {
    public let unarchiveProjectV2Item: Inner
    public struct Inner: Codable, Sendable {
        public let item: NodeID
    }
}

public struct DeleteProjectItemResponse: Codable, Sendable {
    public let deleteProjectV2Item: Inner
    public struct Inner: Codable, Sendable {
        public let deletedItemId: String
    }
}

public struct ProjectItemRef: Codable, Sendable {
    public let id: String
    public let type: String
}

// MARK: ID-lookup envelopes

public struct ViewerIdResponse: Codable, Sendable {
    public let viewer: NodeID
}

public struct UserIdResponse: Codable, Sendable {
    public let user: NodeID?
}

public struct OrganizationIdResponse: Codable, Sendable {
    public let organization: NodeID?
}

public struct RepositoryIdResponse: Codable, Sendable {
    public let repository: NodeID?
}

public struct TeamIdResponse: Codable, Sendable {
    public let organization: TeamContainer?
    public struct TeamContainer: Codable, Sendable {
        public let team: NodeID?
    }
}

public struct CopyProjectResponse: Codable, Sendable {
    public let copyProjectV2: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2: ProjectV2
    }
}

public struct MarkProjectAsTemplateResponse: Codable, Sendable {
    public let markProjectV2AsTemplate: Inner?
    public struct Inner: Codable, Sendable {
        public let projectV2: TemplateState
    }
    public struct TemplateState: Codable, Sendable {
        public let id: String
        public let template: Bool
    }
}

public struct UnmarkProjectAsTemplateResponse: Codable, Sendable {
    public let unmarkProjectV2AsTemplate: Inner?
    public struct Inner: Codable, Sendable {
        public let projectV2: MarkProjectAsTemplateResponse.TemplateState
    }
}

public struct LinkProjectToRepositoryResponse: Codable, Sendable {
    public let linkProjectV2ToRepository: Inner?
    public struct Inner: Codable, Sendable {
        public let repository: RepoStub
    }
    public struct RepoStub: Codable, Sendable {
        public let nameWithOwner: String
    }
}

public struct UnlinkProjectFromRepositoryResponse: Codable, Sendable {
    public let unlinkProjectV2FromRepository: Inner?
    public struct Inner: Codable, Sendable {
        public let repository: LinkProjectToRepositoryResponse.RepoStub
    }
}

public struct LinkProjectToTeamResponse: Codable, Sendable {
    public let linkProjectV2ToTeam: Inner?
    public struct Inner: Codable, Sendable {
        public let team: TeamStub
    }
    public struct TeamStub: Codable, Sendable {
        public let name: String
    }
}

public struct UnlinkProjectFromTeamResponse: Codable, Sendable {
    public let unlinkProjectV2FromTeam: Inner?
    public struct Inner: Codable, Sendable {
        public let team: LinkProjectToTeamResponse.TeamStub
    }
}

public struct CreateFieldResponse: Codable, Sendable {
    public let createProjectV2Field: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2Field: ProjectV2FieldDescriptor
    }
}

public struct DeleteFieldResponse: Codable, Sendable {
    public let deleteProjectV2Field: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2Field: ProjectV2FieldDescriptor
    }
}

public struct UpdateItemFieldValueResponse: Codable, Sendable {
    public let updateProjectV2ItemFieldValue: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2Item: NodeID
    }
}

public struct ClearItemFieldValueResponse: Codable, Sendable {
    public let clearProjectV2ItemFieldValue: Inner
    public struct Inner: Codable, Sendable {
        public let projectV2Item: NodeID
    }
}

public struct ResourceIdResponse: Codable, Sendable {
    public let resource: ResourceNode?
    public struct ResourceNode: Codable, Sendable {
        public let id: String
        public let typename: String

        enum CodingKeys: String, CodingKey {
            case id
            case typename = "__typename"
        }
    }
}

public struct ViewerProjectIdResponse: Codable, Sendable {
    public let viewer: ProjectIdContainer
    public struct ProjectIdContainer: Codable, Sendable {
        public let projectV2: NodeID?
    }
}

public struct UserProjectIdResponse: Codable, Sendable {
    public let user: ProjectIdContainer?
    public struct ProjectIdContainer: Codable, Sendable {
        public let projectV2: NodeID?
    }
}

public struct OrgProjectIdResponse: Codable, Sendable {
    public let organization: ProjectIdContainer?
    public struct ProjectIdContainer: Codable, Sendable {
        public let projectV2: NodeID?
    }
}

// MARK: Field lookup envelope (polymorphic via __typename)

public struct ProjectFieldsResponse: Codable, Sendable {
    public let viewer: FieldContainer?
    public let user: FieldContainer?
    public let organization: FieldContainer?

    public struct FieldContainer: Codable, Sendable {
        public let projectV2: ProjectFieldList?
    }
}

public struct ProjectFieldList: Codable, Sendable {
    public let fields: ProjectFieldConnection
}

public struct ProjectFieldConnection: Codable, Sendable {
    public let totalCount: Int
    public let nodes: [ProjectV2FieldDescriptor]
}

/// One field in a project's columns. Polymorphic by GraphQL type.
public struct ProjectV2FieldDescriptor: Codable, Sendable {
    public let id: String
    public let name: String
    public let dataType: String
    public let typename: String
    public let options: [SingleSelectOption]?

    public struct SingleSelectOption: Codable, Sendable {
        public let id: String
        public let name: String
    }

    enum CodingKeys: String, CodingKey {
        case id, name, dataType, options
        case typename = "__typename"
    }
}
