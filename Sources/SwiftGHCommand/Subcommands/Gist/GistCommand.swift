import ArgumentParser

struct GistCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gist",
        abstract: "Manage gists.",
        subcommands: [GistView.self]
    )
}
