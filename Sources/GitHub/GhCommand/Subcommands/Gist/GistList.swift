import ArgumentParser
import ForgeKit
import ShellKit
import Foundation
import GitHub

struct GistList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List your gists."
    )

    @Option(name: [.short, .customLong("limit")],
            help: "Maximum gists to fetch.")
    var limit: Int = 30

    @Flag(name: .long, help: "Only show public gists.")
    var publicOnly: Bool = false

    @Flag(name: .long, help: "Only show secret gists.")
    var secretOnly: Bool = false

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let client = try await CommandContext.apiClient()
        let perPage = min(limit, 100)
        let gists: [Gist] = try await client.get(
            "gists",
            query: [URLQueryItem(name: "per_page", value: String(perPage))])
        let filtered = gists.filter { gist in
            if publicOnly { return gist.public }
            if secretOnly { return !gist.public }
            return true
        }
        let trimmed = Array(filtered.prefix(limit))

        if trimmed.isEmpty {
            Shell.print("No gists found.")
            return
        }
        let on = color.resolved()
        for g in trimmed {
            let visibility = g.public
                ? StatusBadge.open("public", enabled: on)
                : StatusBadge.draft("secret", enabled: on)
            let files = g.files.keys.sorted().joined(separator: ", ")
            let desc = g.description ?? ""
            let idToken = OSC8.wrap(g.id, url: g.htmlUrl.absoluteString, enabled: on)
            Shell.print("\(idToken)\t\(visibility)\t\(files)\t\(desc)")
        }
    }
}
