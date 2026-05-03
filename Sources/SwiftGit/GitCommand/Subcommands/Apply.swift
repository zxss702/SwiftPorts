import ArgumentParser
import Foundation
import SwiftGit

struct Apply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply a patch to files and/or to the index."
    )

    @Flag(name: .customLong("cached"),
          help: "Apply to the index only; leave the working tree alone.")
    var cached: Bool = false

    @Flag(name: .customLong("index"),
          help: "Apply to BOTH the index and the working tree.")
    var index: Bool = false

    @Argument(help: "Patch file. Use `-` to read from stdin.")
    var patchFile: String?

    func run() async throws {
        let data: Data
        if let patchFile, patchFile != "-" {
            let url = URL(fileURLWithPath: patchFile)
            data = try Data(contentsOf: url)
        } else {
            data = FileHandle.standardInput.availableData
        }

        let location: ApplyLocation = {
            if cached { return .index }
            if index { return .both }
            return .workdir
        }()

        try await CommandContext.gitClient().apply(patch: data, location: location)
        // Real git is silent on success.
    }
}
