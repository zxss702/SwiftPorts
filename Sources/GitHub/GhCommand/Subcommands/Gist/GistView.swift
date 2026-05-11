import ArgumentParser
import GlamKit
import ShellKit
import Foundation
import GitHub

struct GistView: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View a gist."
    )

    @Argument(help: "Gist ID.")
    var id: String

    @Option(name: .customLong("filename"),
            help: "Print just one file from the gist.")
    var filename: String?

    func run() async throws {
        let client = try await CommandContext.apiClient()
        let gist: Gist = try await client.get("gists/\(id)")

        if let filename {
            guard let file = gist.files[filename] else {
                throw ValidationError("Gist has no file '\(filename)'.")
            }
            // `--filename` is the path that scripts use to fetch a
            // single file's raw bytes (`gh gist view ID --filename
            // README.md > local.md`). Run nothing through Glam here
            // — rendering Markdown would change the bytes the user
            // gets, which is a regression vs. the previous raw
            // passthrough. The all-files listing path below still
            // renders for human-readable display.
            if let content = file.content { Shell.print(content) }
            return
        }
        Shell.print("\(gist.id)  \(gist.description ?? "")")
        if let owner = gist.owner ?? gist.user {
            Shell.print("author: @\(owner.login)")
        }
        Shell.print("html: \(gist.htmlUrl.absoluteString)")
        for (name, file) in gist.files.sorted(by: { $0.key < $1.key }) {
            Shell.print("\n# \(name) (\(file.language ?? file.type))")
            if let content = file.content {
                Shell.print(Self.renderFileContent(content, language: file.language))
            } else {
                Shell.print("[truncated, fetch raw at \(file.rawUrl.absoluteString)]")
            }
        }
    }

    /// Run a gist file's content through GlamKit when its `language`
    /// is `"Markdown"` — same rule the upstream `gh` CLI uses for the
    /// all-files listing. Only the human-readable listing path uses
    /// this; the `--filename` path stays raw (see `run`).
    private static func renderFileContent(_ content: String, language: String?) -> String {
        guard language == "Markdown" else { return content }
        return Glam.renderBody(content)
    }
}
