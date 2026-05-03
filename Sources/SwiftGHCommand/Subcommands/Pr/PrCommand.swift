import ArgumentParser

struct PrCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pr",
        abstract: "Manage pull requests.",
        subcommands: [
            PrList.self,
            PrView.self,
            PrCreate.self,
            PrCheckout.self,
            PrMerge.self,
            PrClose.self,
            PrReopen.self,
            PrCommentCommand.self,
        ]
    )
}
