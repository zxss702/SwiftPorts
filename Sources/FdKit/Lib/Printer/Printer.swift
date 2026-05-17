import Foundation
import RipgrepKit
import ShellKit

/// Writes one matched entry per call. Encapsulates the (small) display
/// transformations fd performs on the path before writing it.
struct Printer {

    let options: PrinterOptions

    /// Render and emit `entry`. The metadata snapshot drives
    /// directory-slash decoration and `--type executable` coloring.
    func emit(_ entry: Walker.Entry,
              metadata: EntryFilter.Metadata,
              to stdout: OutputSink) {
        if options.quiet { return }

        var path = path(for: entry)

        if options.directorySlash && metadata.isDirectory && !path.hasSuffix("/") {
            path += "/"
        }

        if let sep = options.pathSeparator, sep != "/" {
            path = path.replacingOccurrences(of: "/", with: sep)
        }

        if options.color {
            path = colorize(path: path, metadata: metadata)
        }

        let terminator: Character = options.print0 ? "\0" : "\n"
        stdout.write(path + String(terminator))
    }

    /// Build the user-facing path string. By default we use the
    /// walker's `displayPath` (carries the literal shape the user
    /// typed); `--absolute-path` and `--strip-cwd-prefix` override.
    private func path(for entry: Walker.Entry) -> String {
        if options.absolutePath {
            return entry.url.standardizedFileURL.path
        }
        var p = entry.displayPath
        if options.stripCwdPrefix && p.hasPrefix("./") {
            p = String(p.dropFirst(2))
        }
        return p
    }

    /// Crude color decoration. fd reads `LS_COLORS` for fine-grained
    /// styling; we apply a small fixed palette (directories blue,
    /// symlinks cyan, executables green) so colored output looks
    /// recognizable without dragging an LS_COLORS parser in. Honors
    /// the same kill switches as ripgrep (`NO_COLOR` is checked at
    /// the CLI layer).
    private func colorize(path: String,
                          metadata: EntryFilter.Metadata) -> String {
        let reset = "\u{1B}[0m"
        if metadata.isDirectory {
            return "\u{1B}[1;34m" + path + reset
        }
        if metadata.isSymlink {
            return "\u{1B}[1;36m" + path + reset
        }
        if let perms = metadata.posixPermissions, (perms & 0o111) != 0 {
            return "\u{1B}[1;32m" + path + reset
        }
        return path
    }
}
