import Foundation
import RipgrepKit
import ShellKit

/// Writes one matched entry per call. Encapsulates the (small) display
/// transformations fd performs on the path before writing it.
struct Printer {

    let options: PrinterOptions
    private let lsColors: LsColors

    init(options: PrinterOptions) {
        self.options = options
        // Resolve LS_COLORS once at construction. Calling
        // `LsColors.fromEnvironment` per entry would re-parse the env
        // var on every match — wasteful when a run produces thousands
        // of entries.
        self.lsColors = options.lsColors ?? LsColors.fromEnvironment()
    }

    /// Render and emit `entry`. The metadata snapshot drives
    /// directory-slash decoration and the LS_COLORS-driven palette.
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
            path = colorize(path: path,
                            basename: entry.url.lastPathComponent,
                            metadata: metadata)
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

    /// Apply the resolved LS_COLORS-style palette to the path. Returns
    /// the input unchanged when no rule applies — matches what real
    /// fd / ls do for entries that fall through to the default style.
    /// Honors the same kill switches as ripgrep (`NO_COLOR` is checked
    /// at the CLI layer; this method only runs when `options.color`
    /// is already true).
    private func colorize(path: String,
                          basename: String,
                          metadata: EntryFilter.Metadata) -> String {
        guard let code = lsColors.code(
            forBasename: basename,
            isDirectory: metadata.isDirectory,
            isSymlink: metadata.isSymlink,
            isRegularFile: metadata.isRegularFile,
            posixPermissions: metadata.posixPermissions,
            fileType: metadata.fileType)
        else { return path }
        return lsColors.wrap(path, with: code)
    }
}
