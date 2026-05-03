import ArgumentParser
import Foundation
import SwiftGHCore

struct ReleaseList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List releases in a repository."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO.")
    var repo: RepositoryReference

    @Option(name: [.short, .customLong("limit")],
            help: "Maximum number of releases to fetch.")
    var limit: Int = 30

    @Flag(name: .long, help: "Print as JSON array.")
    var json: Bool = false

    func run() async throws {
        let client = APIClient()
        let perPage = min(limit, 100)
        let releases: [Release] = try await client.get(
            "repos/\(repo.slug)/releases",
            query: [URLQueryItem(name: "per_page", value: String(perPage))]
        )
        let trimmed = Array(releases.prefix(limit))

        if json {
            print(try CodableOutput.prettyJSON(trimmed))
            return
        }
        if trimmed.isEmpty {
            print("No releases found in \(repo.slug).")
            return
        }
        for r in trimmed {
            let label = r.draft ? "[draft]" : (r.prerelease ? "[pre]" : "       ")
            let when = r.publishedAt.map(ISO8601DateFormatter().string(from:)) ?? "-"
            print("\(label)  \(r.tagName)\t\(r.name ?? "")\t\(when)")
        }
    }
}
