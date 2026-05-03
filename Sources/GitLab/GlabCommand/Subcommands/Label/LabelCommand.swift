import ArgumentParser

struct LabelCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "label",
        abstract: "Manage labels in a project.",
        subcommands: [
            LabelList.self,
            LabelCreate.self,
            LabelDelete.self,
        ]
    )
}
