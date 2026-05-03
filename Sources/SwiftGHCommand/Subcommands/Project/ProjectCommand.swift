import ArgumentParser

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Work with GitHub Projects (V2).",
        subcommands: [
            ProjectList.self,
            ProjectView.self,
            ProjectItemList.self,
            ProjectCreate.self,
            ProjectEdit.self,
            ProjectClose.self,
            ProjectDelete.self,
            ProjectItemAdd.self,
            ProjectItemArchive.self,
            ProjectItemDelete.self,
            ProjectFieldListCommand.self,
        ]
    )
}
