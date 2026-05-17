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

    /// `LS_COLORS`-style style table. When `nil`, the printer reads
    /// `LS_COLORS` (or `DIRCOLORS`, or its built-in default) the first
    /// time it needs to color an entry. Tests / embedders can pin a
    /// specific spec by setting this to a parsed `LsColors`.
    public var lsColors: LsColors? = nil

    /// SGR code applied to the substring of each path that the
    /// pattern matched. Mirrors fd's default of bold red (`01;31`).
    /// Set to `nil` to disable match highlighting entirely while
    /// keeping the rest of the LS_COLORS palette. The empty-pattern
    /// case (`fd` with no PATTERN) never produces a highlight
    /// regardless of this setting.
    public var matchHighlight: String? = "01;31"

    public init() {}
}
