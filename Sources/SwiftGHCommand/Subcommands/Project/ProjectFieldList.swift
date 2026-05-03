import ArgumentParser
import Foundation
import SwiftGHCore

struct ProjectFieldListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "field-list",
        abstract: "List the fields (columns) configured on a ProjectV2."
    )

    @Argument(help: "Project number.")
    var number: Int

    @Option(name: [.customShort("o"), .customLong("owner")])
    var owner: String?

    @Flag(name: [.long, .customLong("org")])
    var asOrg: Bool = false

    @Option(name: [.short, .customLong("limit")]) var limit: Int = 100

    @Flag(name: .long, help: "Print as JSON array.")
    var json: Bool = false

    func run() async throws {
        let gql = try await CommandContext.graphQLClient()
        let connection: ProjectFieldConnection
        if let owner {
            if asOrg {
                let response: ProjectFieldsResponse = try await gql.query(
                    ProjectMutations.orgProjectFields,
                    variables: [
                        "login": .string(owner),
                        "number": .int(number),
                        "first": .int(min(limit, 100)),
                    ])
                guard let p = response.organization?.projectV2 else {
                    throw ValidationError("No project #\(number) on org '\(owner)'.")
                }
                connection = p.fields
            } else {
                let response: ProjectFieldsResponse = try await gql.query(
                    ProjectMutations.userProjectFields,
                    variables: [
                        "login": .string(owner),
                        "number": .int(number),
                        "first": .int(min(limit, 100)),
                    ])
                guard let p = response.user?.projectV2 else {
                    throw ValidationError("No project #\(number) on user '\(owner)'.")
                }
                connection = p.fields
            }
        } else {
            let response: ProjectFieldsResponse = try await gql.query(
                ProjectMutations.viewerProjectFields,
                variables: [
                    "number": .int(number),
                    "first": .int(min(limit, 100)),
                ])
            guard let p = response.viewer?.projectV2 else {
                throw ValidationError("No project #\(number) for current user.")
            }
            connection = p.fields
        }

        if json {
            print(try CodableOutput.prettyJSON(connection.nodes))
            return
        }
        if connection.nodes.isEmpty {
            print("No fields."); return
        }
        for f in connection.nodes {
            let optionsCount = f.options?.count
            let extras = optionsCount.map { "\t(\($0) options)" } ?? ""
            print("\(f.id)\t\(f.dataType)\t\(f.name)\(extras)")
        }
    }
}
