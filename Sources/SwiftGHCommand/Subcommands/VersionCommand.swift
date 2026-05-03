import ArgumentParser

struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the version of SwiftGH."
    )

    func run() async throws {
        print("gh (SwiftGH port) 0.1.0-dev")
        print("https://github.com/cocoanetics/SwiftGH")
    }
}
