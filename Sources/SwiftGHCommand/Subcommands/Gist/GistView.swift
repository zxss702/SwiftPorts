import ArgumentParser
import Foundation
import SwiftGHCore

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

    @Flag(name: .long, help: "Print the JSON response body.")
    var json: Bool = false

    func run() async throws {
        let client = APIClient()
        let gist: Gist = try await client.get("gists/\(id)")

        if json {
            print(try CodableOutput.prettyJSON(gist))
            return
        }
        if let filename {
            guard let file = gist.files[filename] else {
                throw ValidationError("Gist has no file '\(filename)'.")
            }
            if let content = file.content { print(content) }
            return
        }
        print("\(gist.id)  \(gist.description ?? "")")
        if let owner = gist.owner ?? gist.user {
            print("author: @\(owner.login)")
        }
        print("html: \(gist.htmlUrl.absoluteString)")
        for (name, file) in gist.files.sorted(by: { $0.key < $1.key }) {
            print("\n# \(name) (\(file.language ?? file.type))")
            if let content = file.content {
                print(content)
            } else {
                print("[truncated, fetch raw at \(file.rawUrl.absoluteString)]")
            }
        }
    }
}
