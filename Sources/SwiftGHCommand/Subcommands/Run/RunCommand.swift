import ArgumentParser

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "View GitHub Actions runs.",
        subcommands: [
            RunList.self,
            RunView.self,
            RunWatch.self,
            RunDownload.self,
            RunCancel.self,
            RunRerun.self,
            RunDelete.self,
        ]
    )
}
