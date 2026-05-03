import ArgumentParser
import Foundation
import SwiftGHCore

struct PrView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View a pull request."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO.")
    var repo: RepositoryReference

    @Argument(help: "PR number.")
    var number: Int

    @Flag(name: .long, help: "Print the JSON response body.")
    var json: Bool = false

    func run() async throws {
        let client = APIClient()
        let pr: PullRequest = try await client.get(
            "repos/\(repo.slug)/pulls/\(number)")

        if json {
            print(try CodableOutput.prettyJSON(pr))
            return
        }
        print("#\(pr.number)  \(pr.title)")
        print("state: \(pr.state.rawValue)\(pr.draft == true ? " (draft)" : "")  author: @\(pr.user.login)")
        print("\(pr.head.ref) → \(pr.base.ref)")
        print("created: \(ISO8601DateFormatter().string(from: pr.createdAt))")
        if let merged = pr.merged, merged, let when = pr.mergedAt {
            print("merged: \(ISO8601DateFormatter().string(from: when))")
        }
        if !pr.labels.isEmpty {
            print("labels: \(pr.labels.map(\.name).joined(separator: ", "))")
        }
        print("url: \(pr.htmlUrl.absoluteString)")
        if let body = pr.body, !body.isEmpty {
            print("\n--\n\(body)")
        }
    }
}
