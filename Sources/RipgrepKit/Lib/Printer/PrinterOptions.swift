import Foundation

/// Options shared by every printer.
public struct PrinterOptions: Sendable {

    /// Print the file path for each matching line (`-H`/`--with-filename`).
    /// `nil` = printer chooses based on whether multiple paths /
    /// recursion are in play.
    public var withFilename: Bool? = nil

    /// Print line numbers (`-n`/`--line-number`).
    public var lineNumber: Bool = false

    /// Print column numbers (`--column`).
    public var column: Bool = false

    /// Print the byte offset (`-b`/`--byte-offset`).
    public var byteOffset: Bool = false

    /// Group matches under a filename heading (`--heading`).
    public var heading: Bool = false

    /// Quiet mode — suppress output, just signal "any match" via the
    /// exit code (`-q`).
    public var quiet: Bool = false

    /// Use color (auto on TTY).
    public var color: Bool = false

    /// User-supplied color spec from `--colors`.
    public var colorSpec: ColorSpec = .default

    /// Print a NUL byte after each file path (`-0`/`--null`).
    public var nullSeparator: Bool = false

    /// Print only the matched substrings, one per line (`-o`).
    public var onlyMatching: Bool = false

    /// Replace matched text with `replace` (`-r`).
    public var replace: String? = nil

    /// Field separator after the filename (`--field-context-separator` /
    /// `--field-match-separator`). Default `:` for match, `-` for context.
    public var matchFieldSeparator: String = ":"
    public var contextFieldSeparator: String = "-"

    /// Drop lines longer than this (`-M`).
    public var maxColumns: Int? = nil

    /// Show a "[..]" preview for over-long lines instead of skipping.
    public var maxColumnsPreview: Bool = false

    /// Separator between non-adjacent context chunks (`--context-separator`).
    public var contextSeparator: String = "--"

    /// Trim ASCII whitespace from the start of each output line
    /// (`--trim`).
    public var trim: Bool = false

    /// Print all lines (match or not) — `--passthru`.
    public var passthru: Bool = false

    /// Path separator override (`--path-separator`).
    public var pathSeparator: String? = nil

    /// Emit `--include-zero` files in counts summary output.
    public var includeZero: Bool = false

    public init() {}
}

/// User-tweakable color settings. Each role maps to an ANSI escape.
public struct ColorSpec: Sendable {
    public var path: String      // file path
    public var lineNumber: String
    public var matched: String   // matched text
    public var contextLine: String?

    public init(path: String,
                lineNumber: String,
                matched: String,
                contextLine: String? = nil) {
        self.path = path
        self.lineNumber = lineNumber
        self.matched = matched
        self.contextLine = contextLine
    }

    /// Sensible defaults — magenta paths, green line numbers, red
    /// bold matches.
    public static let `default` = ColorSpec(
        path: "\u{1B}[35m",
        lineNumber: "\u{1B}[32m",
        matched: "\u{1B}[1;31m")

    public static let reset = "\u{1B}[0m"
}
