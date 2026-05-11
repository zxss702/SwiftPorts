import ArgumentParser
import ShellKit
import Foundation
import ForgeKit
import GitLab

struct CiList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List recent CI/CD pipelines.",
        aliases: ["ls"]
    )

    @Option(name: [.customShort("R"), .long],
            help: "Repository as OWNER/REPO or GROUP/NAMESPACE/REPO.")
    var repo: RepositoryReference?

    @Option(name: [.customShort("s"), .long],
            help: "Filter by status (running / success / failed / canceled / pending / …).")
    var status: String?

    @Option(name: .long,
            help: "Filter by ref (branch or tag).")
    var ref: String?

    @Option(name: .long,
            help: "Filter by source (push, schedule, web, api, trigger, …).")
    var source: String?

    @Option(name: [.customShort("P"), .customLong("per-page")],
            help: "Items per page.")
    var perPage: Int = 30

    @Option(name: [.customShort("p"), .long],
            help: "Page number.")
    var page: Int = 1

    @Flag(name: .long, help: "Print as JSON array.")
    var json: Bool = false

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let target = try await CommandContext.resolveRepo(flag: repo)
        let client = try await CommandContext.apiClient(host: target.host)

        var query: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        if let ref { query.append(URLQueryItem(name: "ref", value: ref)) }
        if let source { query.append(URLQueryItem(name: "source", value: source)) }

        let pipelines: [Pipeline] = try await client.get(
            "projects/\(target.encodedPath)/pipelines", query: query)

        if json {
            Shell.print(try CodableOutput.prettyJSON(pipelines))
            return
        }
        if pipelines.isEmpty {
            Shell.print("No pipelines match.")
            return
        }
        let on = color.resolved()
        for p in pipelines {
            let age = StatusBadge.muted(CiSupport.ageInWords(from: p.createdAt), enabled: on)
            let refLabel = p.ref ?? "—"
            let sha = String(p.sha.prefix(8))
            let idToken = OSC8.wrap("#\(p.id)", url: p.webUrl.absoluteString, enabled: on)
            Shell.print("\(idToken)\t\(CiSupport.renderStatus(p.status, enabled: on))\t\(refLabel)\t\(sha)\t\(age)")
        }
    }
}
