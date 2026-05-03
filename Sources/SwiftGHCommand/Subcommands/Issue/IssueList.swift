import ArgumentParser
import Foundation
import SwiftGHCore

struct IssueList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List and filter issues."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO.")
    var repo: RepositoryReference

    @Option(name: [.short, .customLong("state")],
            help: "Filter by state.")
    var state: IssueListState = .open

    @Option(name: [.short, .customLong("limit")],
            help: "Maximum number of issues to fetch.")
    var limit: Int = 30

    @Option(name: [.short, .customLong("label")],
            parsing: .singleValue,
            help: "Filter by label; repeatable.")
    var labels: [String] = []

    @Option(name: .customLong("author"),
            help: "Filter by author login.")
    var author: String?

    @Flag(name: .long, help: "Print as JSON array.")
    var json: Bool = false

    func run() async throws {
        let client = APIClient()
        let perPage = min(limit, 100)
        var query: [URLQueryItem] = [
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if !labels.isEmpty {
            query.append(URLQueryItem(name: "labels", value: labels.joined(separator: ",")))
        }
        if let author { query.append(URLQueryItem(name: "creator", value: author)) }

        let issues: [Issue] = try await client.get(
            "repos/\(repo.slug)/issues", query: query)
        // The /issues endpoint returns PRs too — drop them.
        let onlyIssues = issues.filter { $0.pullRequest == nil }
        let trimmed = Array(onlyIssues.prefix(limit))

        if json {
            print(try CodableOutput.prettyJSON(trimmed))
            return
        }
        if trimmed.isEmpty {
            print("No issues match.")
            return
        }
        for i in trimmed {
            print("#\(i.number)\t\(i.state.rawValue)\t\(i.title)\t@\(i.user.login)")
        }
    }
}

enum IssueListState: String, ExpressibleByArgument, Sendable {
    case open, closed, all
}
