import ArgumentParser
import Foundation
import SwiftGHCore

struct ReleaseView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View information about a release.",
        discussion: "Without TAG, the latest non-draft, non-prerelease is shown."
    )

    @Option(name: [.short, .long],
            help: "Repository as OWNER/REPO.")
    var repo: RepositoryReference

    @Argument(help: "Tag name. Omit for the latest release.")
    var tag: String?

    @Flag(name: .long, help: "Print the JSON response body.")
    var json: Bool = false

    func run() async throws {
        let client = APIClient()
        let path = tag.map { "repos/\(repo.slug)/releases/tags/\($0)" }
            ?? "repos/\(repo.slug)/releases/latest"
        let release: Release = try await client.get(path)

        if json {
            print(try CodableOutput.prettyJSON(release))
            return
        }
        print("\(release.tagName)  \(release.name ?? "")")
        if let when = release.publishedAt {
            print("published: \(ISO8601DateFormatter().string(from: when))")
        }
        print("author: @\(release.author.login)")
        print("url: \(release.htmlUrl.absoluteString)")
        if !release.assets.isEmpty {
            print("\nassets:")
            for a in release.assets {
                let size = ByteCountFormatter.string(
                    fromByteCount: a.size, countStyle: .file)
                print("  \(a.name)  (\(size))  \(a.browserDownloadUrl.absoluteString)")
            }
        }
        if let body = release.body, !body.isEmpty {
            print("\n--\n\(body)")
        }
    }
}
