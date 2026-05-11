import ArgumentParser
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
            if let content = file.content {
                Shell.print(Self.renderFileContent(content, language: file.language))
            }
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
    /// is `"Markdown"` — same rule the upstream `gh` CLI uses. Any
    /// other language (code, plain text, …) prints as-is so syntax
    /// stays valid for downstream processing.
    private static func renderFileContent(_ content: String, language: String?) -> String {
        guard language == "Markdown" else { return content }
        return MarkdownBody.render(content)
    }
}
