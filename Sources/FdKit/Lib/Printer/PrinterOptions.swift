import Foundation

/// Output-shape knobs for fd's printer. Each one maps onto a flag
/// users tune at the CLI layer.
public struct PrinterOptions: Sendable {

    /// Resolved color decision. `nil` means "auto" — the engine asks
    /// `ColorChoice` at run-time. The CLI parser resolves to a concrete
    /// `true`/`false` before construction so the engine doesn't need to
    /// re-evaluate the TTY state.
    public var color: Bool = false

    /// Terminate each path with `\0` instead of `\n` (`-0` / `--print0`).
    public var print0: Bool = false

    /// Emit absolute paths (`-a` / `--absolute-path`).
    public var absolutePath: Bool = false

    /// Strip a leading `./` from each printed path
    /// (`--strip-cwd-prefix`). The walker default for an implicit-cwd
    /// search is to emit `./<path>`; this strips that prefix for users
    /// who pipe into other tools.
    public var stripCwdPrefix: Bool = false

    /// `--path-separator=SEP`. Replace `/` with this separator in the
    /// printed output. Primarily a Windows compatibility knob.
    public var pathSeparator: String? = nil

    /// Suppress output entirely (`-q` / `--quiet`). The engine still
    /// walks; the CLI exit code reflects whether anything matched.
    public var quiet: Bool = false

    /// Suffix directories with `/` in the listing — fd does this when
    /// stdout is a TTY so users can tell entries apart at a glance.
    public var directorySlash: Bool = true

    public init() {}
}
