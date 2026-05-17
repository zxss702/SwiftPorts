import Foundation

/// Options that govern per-file scanning behaviour.
public struct SearchOptions: Sendable {

    /// Lines of context to print before each match (`-B`).
    public var beforeContext: Int = 0
    /// Lines of context to print after each match (`-A`).
    public var afterContext: Int = 0

    /// Stop searching a file after this many matching lines (`-m`).
    /// `nil` = unlimited.
    public var maxCount: Int? = nil

    /// Treat binary files as text (`-a`/`--text`).
    public var binaryAsText: Bool = false

    /// Search inside binary files but still flag them (`--binary`).
    /// When false, hitting a NUL byte stops the file search and emits
    /// the standard "binary file matches" message.
    public var searchBinary: Bool = false

    /// Treat CR/LF as `\n` (`--crlf`). Lines that arrive with a
    /// trailing `\r` get it trimmed before the matcher sees them.
    public var crlf: Bool = false

    /// Use NUL instead of `\n` as the line separator (`--null-data`).
    public var nullData: Bool = false

    /// Stop searching a file on the first non-matching line
    /// (`--stop-on-nonmatch`). Useful with `--passthru` for log
    /// tailing.
    public var stopOnNonmatch: Bool = false

    /// Encoding override (`-E`/`--encoding`). Default is "auto" — we
    /// try BOM detection then fall back to UTF-8 with lossy decoding.
    public var encoding: String.Encoding? = nil

    public init() {}
}
