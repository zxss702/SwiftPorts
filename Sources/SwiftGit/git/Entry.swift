import Foundation
import ArgumentParser
import GitCommand
import Sandbox

@main
struct Entry {
    static func main() async {
        do {
            // Real git accepts attached short-option-with-value forms
            // like `-U3` (= `-U 3`). ArgumentParser doesn't support
            // those for typed options, so split them out before parsing.
            let argv = Self.preprocess(Array(Sandbox.arguments.dropFirst()))
            var cmd = try GitCommand.parseAsRoot(argv)
            if var asyncCmd = cmd as? any AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try cmd.run()
            }
        } catch let cli as CLIError {
            cli.emitAndExit()
        } catch {
            // Hand off to ArgumentParser's default formatter for usage
            // errors / validation failures; preserves help output etc.
            GitCommand.exit(withError: error)
        }
    }

    /// Split git's attached short-option-with-value forms into separate
    /// tokens so ArgumentParser can parse them.
    /// - `-U<n>` → `-U <n>` (diff context lines)
    /// - `-<n>` → `-n <n>` (log count limit) — only for the `log`
    ///   subcommand, since `-1` etc. aren't generic git shorthand.
    static func preprocess(_ args: [String]) -> [String] {
        var out: [String] = []
        out.reserveCapacity(args.count)
        let isLog = args.first == "log"
        for arg in args {
            if arg.count > 2, arg.hasPrefix("-U"),
               arg.dropFirst(2).allSatisfy(\.isNumber) {
                out.append("-U")
                out.append(String(arg.dropFirst(2)))
                continue
            }
            // For `git log`, accept real-git's `-<n>` shorthand as
            // `-n <n>`. Don't apply globally — `-1` could be a valid
            // negative-int positional in another subcommand.
            if isLog, arg.count > 1, arg.hasPrefix("-"),
               arg.dropFirst().allSatisfy(\.isNumber) {
                out.append("-n")
                out.append(String(arg.dropFirst()))
                continue
            }
            out.append(arg)
        }
        return out
    }
}
