import ArgumentParser
import ForgeKit
import GlamKit
import ShellKit
import Foundation
import GitHub

struct ReleaseView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View information about a release.",
        discussion: "Without TAG, the latest non-draft, non-prerelease is shown."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO. Defaults to the current directory's git remote.")
    var repo: RepositoryReference?

    @Argument(help: "Tag name. Omit for the latest release.")
    var tag: String?

    @Option(name: .long,
            help: "Output JSON with the specified fields (comma-separated).")
    var json: String?

    @Option(name: .customLong("color"),
            help: "Colorize output: always, auto (default), or never.")
    var color: ColorChoice = .auto

    func run() async throws {
        let target = try await RepositoryResolver.resolve(flag: repo)
        let client = try await CommandContext.apiClient()
        let path = tag.map { "repos/\(target.slug)/releases/tags/\($0)" }
            ?? "repos/\(target.slug)/releases/latest"
        let release: Release = try await client.get(path)

        if let json {
            let fields = try JSONFieldSelector.parse(raw: json, fieldMap: ReleaseFields.map)
            let latestTag: String?
            if fields.contains("isLatest") {
                latestTag = await ReleaseList.latestReleaseTag(client: client, slug: target.slug)
            } else {
                latestTag = nil
            }
            let context = ReleaseFields.Context(release: release, latestTag: latestTag)
            Shell.print(try JSONFieldSelector.render(item: context, fields: fields, fieldMap: ReleaseFields.map))
            return
        }

        let on = color.resolved()
        let tagToken = OSC8.wrap(release.tagName, url: release.htmlUrl.absoluteString, enabled: on)
        Shell.print("\(ANSI.bold(tagToken))  \(release.name ?? "")")
        if release.draft {
            Shell.print("state: \(StatusBadge.draft(enabled: on))")
        } else if release.prerelease {
            Shell.print("state: \(StatusBadge.inProgress("pre-release", enabled: on))")
        }
        if let when = release.publishedAt {
            Shell.print("published: \(StatusBadge.muted(ISO8601DateFormatter().string(from: when), enabled: on))")
        }
        Shell.print("author: @\(release.author.login)")
        Shell.print("url: \(release.htmlUrl.absoluteString)")
        if !release.assets.isEmpty {
            Shell.print("\nassets:")
            for a in release.assets {
                let size = ByteCountFormatter.string(
                    fromByteCount: a.size, countStyle: .file)
                Shell.print("  \(a.name)  (\(size))  \(a.browserDownloadUrl.absoluteString)")
            }
        }
        if let body = release.body, !body.isEmpty {
            Shell.print("\n--\n\(Glam.renderBody(body))")
        }
    }
}
