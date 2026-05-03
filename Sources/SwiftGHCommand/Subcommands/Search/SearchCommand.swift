import ArgumentParser

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search GitHub.",
        subcommands: [SearchRepos.self]
    )
}
