import ArgumentParser
import GlamKit
import ShellKit
import Foundation
import ForgeKit
import GitLab

struct IssueView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Display an issue.",
        aliases: ["show"]
    )

    @Option(name: [.customShort("R"), .long],
            help: "Repository as OWNER/REPO or GROUP/NAMESPACE/REPO.")
    var repo: RepositoryReference?

    @Argument(help: "Issue IID, `#IID`, or full issue URL.")
    var issue: String

    @Flag(name: [.customShort("w"), .long],
          help: "Open the issue in the default browser.")
    var web: Bool = false

    @Flag(name: [.customShort("c"), .long],
          help: "Show comments and activity.")
    var comments: Bool = false

    @Flag(name: .long, help: "Print as JSON.")
    var json: Bool = false

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let parsed = try IssueArgument.parse(issue)
        let target: RepositoryReference
        if let fromURL = parsed.repoFromURL {
            target = fromURL
        } else {
            target = try await CommandContext.resolveRepo(flag: repo)
        }

        let client = try await CommandContext.apiClient(host: target.host)
        let issue: Issue = try await client.get(
            "projects/\(target.encodedPath)/issues/\(parsed.iid)")

        if web {
            try await Browser.open(issue.webUrl)
            Shell.print("Opening \(issue.webUrl.absoluteString) in your browser.")
            return
        }

        // Fetch notes upfront when --comments was passed so they're
        // available for both the pretty-print and the JSON paths.
        let notes: [Note]? = comments
            ? try await client.get(
                "projects/\(target.encodedPath)/issues/\(parsed.iid)/notes",
                query: [URLQueryItem(name: "sort", value: "asc")])
            : nil
        let userNotes = notes?.filter { !$0.system }

        if json {
            if let userNotes {
                Shell.print(try CodableOutput.prettyJSON(
                    IssueWithComments(issue: issue, comments: userNotes)))
            } else {
                Shell.print(try CodableOutput.prettyJSON(issue))
            }
            return
        }

        let on = color.resolved()
        let stateLabel: String = issue.state == .opened
            ? StatusBadge.open("opened", enabled: on)
            : StatusBadge.closed(issue.state.rawValue, enabled: on)
        let iidToken = OSC8.wrap("#\(issue.iid)", url: issue.webUrl.absoluteString, enabled: on)
        Shell.print("\(ANSI.bold(iidToken))  \(ANSI.bold(issue.title))")
        let authorBit = issue.author.map { "@\($0.username)" } ?? "—"
        Shell.print("state: \(stateLabel)  author: \(authorBit)")
        if let createdAt = issue.createdAt {
            Shell.print("created: \(ISO8601DateFormatter().string(from: createdAt))")
        }
        if !issue.labels.isEmpty {
            Shell.print("labels: \(issue.labels.joined(separator: ", "))")
        }
        if let milestone = issue.milestone {
            Shell.print("milestone: \(milestone.title)")
        }
        Shell.print("url: \(issue.webUrl.absoluteString)")
        if let body = issue.description, !body.isEmpty {
            Shell.print("\n--\n\(Glam.renderBody(body))")
        }

        if let userNotes {
            guard !userNotes.isEmpty else {
                Shell.print("\n(no comments)")
                return
            }
            Shell.print("\n--- comments ---")
            for note in userNotes {
                let when = note.createdAt.map(ISO8601DateFormatter().string(from:)) ?? "?"
                Shell.print("\n@\(note.author.username)  \(ANSI.dim(when))")
                Shell.print(Glam.renderBody(note.body))
            }
        }
    }
}

/// `--comments --json` output shape: the issue's fields at the top
/// level, plus a sibling `"comments"` array. Flat shape so existing
/// pipes (`jq '.iid'`, `.title`, `.webUrl`) keep working.
private struct IssueWithComments: Encodable {
    let issue: Issue
    let comments: [Note]

    private enum ExtraKeys: String, CodingKey { case comments }

    func encode(to encoder: Encoder) throws {
        try issue.encode(to: encoder)
        var container = encoder.container(keyedBy: ExtraKeys.self)
        try container.encode(comments, forKey: .comments)
    }
}
