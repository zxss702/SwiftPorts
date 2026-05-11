import ArgumentParser
import ShellKit
import Foundation
import ForgeKit
import GitLab

struct MrList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List merge requests.",
        aliases: ["ls"]
    )

    @Option(name: [.customShort("R"), .long],
            help: "Repository as OWNER/REPO or GROUP/NAMESPACE/REPO.")
    var repo: RepositoryReference?

    @Option(name: [.customShort("a"), .long],
            help: "Filter by assignee username.")
    var assignee: String?

    @Option(name: .long,
            help: "Filter by author username.")
    var author: String?

    @Option(name: .long,
            help: "Filter by reviewer username.")
    var reviewer: String?

    @Option(name: [.customShort("l"), .customLong("label")],
            parsing: .singleValue,
            help: "Filter by label; repeatable.")
    var labels: [String] = []

    @Option(name: [.customShort("m"), .long],
            help: "Filter by milestone title.")
    var milestone: String?

    @Option(name: .long, help: "Filter by source branch.")
    var sourceBranch: String?

    @Option(name: .long, help: "Filter by target branch.")
    var targetBranch: String?

    @Option(name: .long, help: "Search the title and description.")
    var search: String?

    @Flag(name: [.customShort("A"), .long],
          help: "Get all merge requests regardless of state.")
    var all: Bool = false

    @Flag(name: [.customShort("c"), .long],
          help: "Get only closed merge requests.")
    var closed: Bool = false

    @Flag(name: [.customShort("M"), .customLong("merged")],
          help: "Get only merged merge requests.")
    var merged: Bool = false

    @Flag(name: .long, help: "Filter by draft (work-in-progress).")
    var draft: Bool = false

    @Option(name: [.customShort("P"), .customLong("per-page")],
            help: "Items per page.")
    var perPage: Int = 30

    @Option(name: [.customShort("p"), .long],
            help: "Page number.")
    var page: Int = 1

    @Flag(name: .long, help: "Print as JSON array.")
    var json: Bool = false

    func run() async throws {
        let target = try await CommandContext.resolveRepo(flag: repo)
        let client = try await CommandContext.apiClient(host: target.host)

        let state: String
        if all { state = "all" }
        else if merged { state = "merged" }
        else if closed { state = "closed" }
        else { state = "opened" }

        var query: [URLQueryItem] = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let assignee {
            query.append(URLQueryItem(name: "assignee_username", value: assignee))
        }
        if let author {
            query.append(URLQueryItem(name: "author_username", value: author))
        }
        if let reviewer {
            query.append(URLQueryItem(name: "reviewer_username", value: reviewer))
        }
        if !labels.isEmpty {
            query.append(URLQueryItem(name: "labels", value: labels.joined(separator: ",")))
        }
        if let milestone {
            query.append(URLQueryItem(name: "milestone", value: milestone))
        }
        if let sourceBranch {
            query.append(URLQueryItem(name: "source_branch", value: sourceBranch))
        }
        if let targetBranch {
            query.append(URLQueryItem(name: "target_branch", value: targetBranch))
        }
        if let search {
            query.append(URLQueryItem(name: "search", value: search))
        }
        if draft {
            query.append(URLQueryItem(name: "wip", value: "yes"))
        }

        let mrs: [MergeRequest] = try await client.get(
            "projects/\(target.encodedPath)/merge_requests", query: query)

        if json {
            Shell.print(try CodableOutput.prettyJSON(mrs))
            return
        }
        if mrs.isEmpty {
            Shell.print("No merge requests match.")
            return
        }
        let on = TTY.isStdoutColorEnabled
        for mr in mrs {
            let iidToken = OSC8.wrap("!\(mr.iid)", url: mr.webUrl.absoluteString, enabled: on)
            let stateLabel = MrSupport.renderState(mr.state, enabled: on)
            // Honor `--color=never` here too — bare `ANSI.dim` /
            // `ANSI.cyan` gate only on `TTY.isStdoutColorEnabled`, so
            // they'd still emit escapes on a TTY when the user asked
            // for plain output.
            let branchSpan = "[\(mr.sourceBranch) → \(mr.targetBranch)]"
            let branch = on ? ANSI.dim(branchSpan) : branchSpan
            let labelChunk: String
            if mr.labels.isEmpty {
                labelChunk = ""
            } else {
                let raw = "(\(mr.labels.joined(separator: ", ")))"
                labelChunk = "  " + (on ? ANSI.cyan(raw) : raw)
            }
            Shell.print("\(iidToken)\t\(stateLabel)\t\(mr.title)\t\(branch)\(labelChunk)")
        }
    }
}
