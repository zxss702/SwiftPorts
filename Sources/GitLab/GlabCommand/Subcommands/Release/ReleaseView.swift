import ArgumentParser
import ForgeKit
import GlamKit
import ShellKit
import Foundation
import GitLab

struct ReleaseView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "Show details of a single release."
    )

    @Option(name: [.customShort("R"), .long],
            help: "Repository as OWNER/REPO or GROUP/NAMESPACE/REPO.")
    var repo: RepositoryReference?

    @Argument(help: "Tag name (e.g. `v1.0.0`).")
    var tagName: String

    @Flag(name: .long, help: "Print the JSON response body.")
    var json: Bool = false

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let target = try await CommandContext.resolveRepo(flag: repo)
        let client = try await CommandContext.apiClient(host: target.host)
        let encoded = tagName.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? tagName
        let release: Release = try await client.get(
            "projects/\(target.encodedPath)/releases/\(encoded)")
        if json {
            Shell.print(try CodableOutput.prettyJSON(release))
            return
        }

        let on = color.resolved()
        let title = release.name ?? release.tagName
        if let url = release._links?.selfLink {
            Shell.print(OSC8.wrap(title, url: url.absoluteString, enabled: on))
        } else {
            Shell.print(title)
        }
        Shell.print("tag: \(release.tagName)")
        if let when = release.releasedAt {
            Shell.print("released: \(StatusBadge.muted(ISO8601DateFormatter().string(from: when), enabled: on))")
        }
        if let author = release.author {
            Shell.print("author: @\(author.username)")
        }
        if let body = release.description, !body.isEmpty {
            Shell.print("\n\(Glam.renderBody(body))")
        }
        if let links = release.assets?.links, !links.isEmpty {
            Shell.print("\nassets:")
            for link in links { Shell.print("  \(link.name): \(link.url.absoluteString)") }
        }
    }
}
