import ArgumentParser
import Foundation
import SwiftGHCore

struct PrList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List and filter pull requests."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO.")
    var repo: RepositoryReference

    @Option(name: [.short, .customLong("state")],
            help: "Filter by state.")
    var state: PrListState = .open

    @Option(name: [.short, .customLong("limit")],
            help: "Maximum number of PRs to fetch.")
    var limit: Int = 30

    @Option(name: .customLong("base"),
            help: "Filter by base branch.")
    var base: String?

    @Flag(name: .long, help: "Print as JSON array.")
    var json: Bool = false

    func run() async throws {
        let client = APIClient()
        let perPage = min(limit, 100)
        var query: [URLQueryItem] = [
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let base { query.append(URLQueryItem(name: "base", value: base)) }

        let prs: [PullRequest] = try await client.get(
            "repos/\(repo.slug)/pulls", query: query)
        let trimmed = Array(prs.prefix(limit))

        if json {
            print(try CodableOutput.prettyJSON(trimmed))
            return
        }
        if trimmed.isEmpty {
            print("No pull requests match.")
            return
        }
        for p in trimmed {
            print("#\(p.number)\t\(p.state.rawValue)\t\(p.title)\t@\(p.user.login)\t\(p.head.ref)→\(p.base.ref)")
        }
    }
}

enum PrListState: String, ExpressibleByArgument, Sendable {
    case open, closed, all
}
