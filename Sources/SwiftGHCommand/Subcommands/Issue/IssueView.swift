import ArgumentParser
import Foundation
import SwiftGHCore

struct IssueView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View an issue."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO.")
    var repo: RepositoryReference

    @Argument(help: "Issue number.")
    var number: Int

    @Flag(name: .long, help: "Print the JSON response body.")
    var json: Bool = false

    func run() async throws {
        let client = APIClient()
        let issue: Issue = try await client.get(
            "repos/\(repo.slug)/issues/\(number)")

        if json {
            print(try CodableOutput.prettyJSON(issue))
            return
        }
        print("#\(issue.number)  \(issue.title)")
        print("state: \(issue.state.rawValue)  author: @\(issue.user.login)")
        print("created: \(ISO8601DateFormatter().string(from: issue.createdAt))")
        if !issue.labels.isEmpty {
            print("labels: \(issue.labels.map(\.name).joined(separator: ", "))")
        }
        print("url: \(issue.htmlUrl.absoluteString)")
        if let body = issue.body, !body.isEmpty {
            print("\n--\n\(body)")
        }
    }
}
