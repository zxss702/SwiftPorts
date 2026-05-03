import Foundation
import SwiftGHCore

/// Resolve owner/project numbers into the GraphQL node IDs project
/// mutations expect. Centralises the dance every project-write command
/// would otherwise repeat.
struct ProjectIDs {

    enum Owner {
        case viewer
        case user(String)
        case organization(String)
    }

    /// Look up the owner's node ID. `viewer` requires no extra arg.
    static func ownerID(_ owner: Owner, gql: GraphQLClient) async throws -> String {
        switch owner {
        case .viewer:
            let response: ViewerIdResponse = try await gql.query(ProjectMutations.viewerId)
            return response.viewer.id
        case .user(let login):
            let response: UserIdResponse = try await gql.query(
                ProjectMutations.userId, variables: ["login": .string(login)])
            guard let id = response.user?.id else {
                throw ProjectIDError.noSuchUser(login)
            }
            return id
        case .organization(let login):
            let response: OrganizationIdResponse = try await gql.query(
                ProjectMutations.organizationId, variables: ["login": .string(login)])
            guard let id = response.organization?.id else {
                throw ProjectIDError.noSuchOrg(login)
            }
            return id
        }
    }

    /// Look up a project's node ID by owner + number.
    static func projectID(
        owner: Owner, number: Int, gql: GraphQLClient
    ) async throws -> String {
        switch owner {
        case .viewer:
            let response: ViewerProjectIdResponse = try await gql.query(
                ProjectMutations.viewerProjectId,
                variables: ["number": .int(number)])
            guard let id = response.viewer.projectV2?.id else {
                throw ProjectIDError.noSuchProject(owner: "viewer", number: number)
            }
            return id
        case .user(let login):
            let response: UserProjectIdResponse = try await gql.query(
                ProjectMutations.userProjectId,
                variables: ["login": .string(login), "number": .int(number)])
            guard let id = response.user?.projectV2?.id else {
                throw ProjectIDError.noSuchProject(owner: login, number: number)
            }
            return id
        case .organization(let login):
            let response: OrgProjectIdResponse = try await gql.query(
                ProjectMutations.orgProjectId,
                variables: ["login": .string(login), "number": .int(number)])
            guard let id = response.organization?.projectV2?.id else {
                throw ProjectIDError.noSuchProject(owner: login, number: number)
            }
            return id
        }
    }

    /// Resolve any GitHub URL (issue/PR) into its node ID.
    static func resourceID(url: URL, gql: GraphQLClient) async throws -> String {
        let response: ResourceIdResponse = try await gql.query(
            ProjectMutations.resourceId,
            variables: ["url": .string(url.absoluteString)])
        guard let id = response.resource?.id else {
            throw ProjectIDError.noSuchResource(url.absoluteString)
        }
        return id
    }
}

enum ProjectIDError: Error, LocalizedError {
    case noSuchUser(String)
    case noSuchOrg(String)
    case noSuchProject(owner: String, number: Int)
    case noSuchResource(String)

    var errorDescription: String? {
        switch self {
        case .noSuchUser(let login):
            return "No user named '\(login)'."
        case .noSuchOrg(let login):
            return "No organization named '\(login)'."
        case .noSuchProject(let owner, let number):
            return "No project #\(number) for owner '\(owner)'."
        case .noSuchResource(let url):
            return "GitHub couldn't resolve \(url) to an issue or PR."
        }
    }
}
