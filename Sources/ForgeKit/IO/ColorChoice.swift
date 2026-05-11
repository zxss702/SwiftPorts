import ArgumentParser
import ShellKit

/// Tri-state `--color=<when>` argument shared by every CLI in
/// SwiftPorts (gh, glab, git, …). Bind in any AsyncParsableCommand:
///
///     @Option(name: .customLong("color"),
///             help: "Colorize output: always, auto (default), or never.")
///     var color: ColorChoice = .auto
///
/// Then call `color.resolved()` once at run-time to get the on/off
/// decision honoring `NO_COLOR` / `CLICOLOR_FORCE` / TTY state.
///
/// The resolution order matches real git:
///   1. The flag's literal value, when not `auto`.
///   2. `NO_COLOR` env (kill switch).
///   3. `CLICOLOR_FORCE` env (force on).
///   4. Whether stdout is a TTY.
///
/// `auto` is the default — matches `color.ui=auto` in git's own
/// config.
public enum ColorChoice: String, ExpressibleByArgument, Sendable, CaseIterable {
    case auto, always, never

    public init?(argument: String) {
        switch argument.lowercased() {
        case "auto":              self = .auto
        case "always", "true":    self = .always
        case "never", "false":    self = .never
        default: return nil
        }
    }

    /// Resolve to a concrete on/off decision for the active stream.
    public func resolved() -> Bool {
        switch self {
        case .always: return true
        case .never:  return false
        case .auto:
            if let v = Shell.env("NO_COLOR"),       !v.isEmpty       { return false }
            if let v = Shell.env("CLICOLOR_FORCE"), !v.isEmpty, v != "0" { return true }
            return TTY.isStdoutTTY
        }
    }
}
