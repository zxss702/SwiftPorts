import Foundation
import ShellKit

/// `LS_COLORS` / `DIRCOLORS`-compatible style table.
///
/// The spec is a colon-separated list of `key=SGR` pairs, where `key`
/// is either a two-letter indicator name (`di`, `ln`, `ex`, …) or a
/// shell-glob suffix pattern (`*.cpp`, `*.tar.gz`, …) and `SGR` is an
/// ANSI Select-Graphic-Rendition parameter string (`01;34`, `38;5;202`,
/// `38;2;255;100;50`, …). Example:
///
/// ```
/// LS_COLORS="di=01;34:ln=01;36:*.cpp=01;33:ex=01;32"
/// ```
///
/// The lookup is allocation-free per call once parsed: indicator
/// keys live in a dictionary, suffix keys live in an array we walk
/// linearly. Extension matching is case-insensitive by convention —
/// upstream coreutils does the same.
///
/// We only implement the widely-supported subset: two-letter type
/// codes and `*.<suffix>` extension patterns. The more exotic
/// indicators (`ca` capability, `mh` multi-hardlink, `do` door) are
/// recognized in the schema but rarely populated.
public struct LsColors: Sendable {

    /// Two-letter indicator → SGR. Includes both the standard set and
    /// the few extra keys we honor for completeness.
    public enum Indicator: String, Sendable {
        case normal            = "no"
        case file              = "fi"
        case directory         = "di"
        case symlink           = "ln"
        case orphanSymlink     = "or"
        case missingTarget     = "mi"
        case pipe              = "pi"
        case socket            = "so"
        case blockDevice       = "bd"
        case charDevice        = "cd"
        case executable        = "ex"
        case setuid            = "su"
        case setgid            = "sg"
        case stickyOtherWrite  = "tw"
        case otherWritable     = "ow"
        case sticky            = "st"
        case multiHardlink     = "mh"
        case door              = "do"
        case capability        = "ca"
        case leftBracket       = "lc"
        case rightBracket      = "rc"
        case endCode           = "ec"
        case reset             = "rs"
    }

    private let indicators: [Indicator: String]
    private let suffixes: [(suffix: String, code: String)]

    /// Reset escape, configurable via the `rs` key. Defaults to the
    /// vanilla SGR-0 reset.
    public var resetEscape: String {
        if let custom = indicators[.reset], !custom.isEmpty {
            return "\u{1B}[\(custom)m"
        }
        return "\u{1B}[0m"
    }

    /// Parse an `LS_COLORS`-formatted string. Unknown indicator keys
    /// are dropped silently — same as coreutils — so a forward-compat
    /// LS_COLORS doesn't crash on a key we don't recognize.
    public init(spec: String) {
        var ind: [Indicator: String] = [:]
        var sfx: [(String, String)] = []
        for raw in spec.split(separator: ":",
                              omittingEmptySubsequences: true) {
            let entry = String(raw)
            guard let eq = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<eq])
            let value = String(entry[entry.index(after: eq)...])
            if value.isEmpty { continue }
            if key.hasPrefix("*.") {
                // Lowercase the suffix once at parse time so the per-
                // entry compare is case-folded for free.
                let suf = String(key.dropFirst(2)).lowercased()
                if !suf.isEmpty {
                    sfx.append((suf, value))
                }
            } else if key.hasPrefix("*") {
                // `*foo` style — match anywhere in the basename. Treat
                // it as a suffix match for simplicity; coreutils does
                // the same here.
                let suf = String(key.dropFirst()).lowercased()
                if !suf.isEmpty {
                    sfx.append((suf, value))
                }
            } else if let i = Indicator(rawValue: key) {
                ind[i] = value
            }
        }
        self.indicators = ind
        self.suffixes = sfx
    }

    /// Snapshot the value of the relevant environment variable. Falls
    /// back through `LS_COLORS` → `DIRCOLORS` → built-in default. The
    /// default mirrors the original fixed palette (dirs blue, symlinks
    /// cyan, executables green) so behavior under an empty environment
    /// stays stable.
    public static func fromEnvironment() -> LsColors {
        if let v = Shell.env("LS_COLORS"), !v.isEmpty {
            return LsColors(spec: v)
        }
        if let v = Shell.env("DIRCOLORS"), !v.isEmpty {
            return LsColors(spec: v)
        }
        return LsColors(spec: defaultSpec)
    }

    /// Resolve the SGR code for an entry. Returns `nil` when no rule
    /// applies (caller should leave the path unstyled).
    public func code(forBasename basename: String,
                     isDirectory: Bool,
                     isSymlink: Bool,
                     isRegularFile: Bool,
                     posixPermissions: Int?,
                     fileType: FileAttributeType?) -> String? {

        // Indicator order matches what coreutils does: special types
        // first, then suid/sgid, then by-extension matches, then `fi`.
        if isSymlink            { return indicators[.symlink] }
        if isDirectory {
            if let perms = posixPermissions {
                // 0o002 = other-write, 0o1000 = sticky. (`0o001` is
                // other-execute, which doesn't affect ls coloring —
                // easy bit to mix up.)
                let otherWrite = (perms & 0o002) != 0
                let sticky = (perms & 0o1000) != 0
                if otherWrite && sticky {
                    return indicators[.stickyOtherWrite]
                        ?? indicators[.directory]
                }
                if otherWrite {
                    return indicators[.otherWritable]
                        ?? indicators[.directory]
                }
                if sticky {
                    return indicators[.sticky] ?? indicators[.directory]
                }
            }
            return indicators[.directory]
        }
        if fileType == .typeBlockSpecial      { return indicators[.blockDevice] }
        if fileType == .typeCharacterSpecial  { return indicators[.charDevice] }
        if fileType == .typeSocket            { return indicators[.socket] }
        // Foundation doesn't model FIFO directly across all SDKs;
        // EntryFilter falls back to a `lstat` probe. If the caller has
        // already classified the entry as a pipe, treat unknown as
        // pipe-like.
        if fileType == .typeUnknown && !isRegularFile {
            return indicators[.pipe]
        }

        if isRegularFile {
            if let perms = posixPermissions {
                if (perms & 0o4000) != 0 {
                    return indicators[.setuid] ?? indicators[.executable]
                }
                if (perms & 0o2000) != 0 {
                    return indicators[.setgid] ?? indicators[.executable]
                }
                if (perms & 0o111) != 0 {
                    return indicators[.executable]
                }
            }
            let lower = basename.lowercased()
            for (suffix, code) in suffixes where lower.hasSuffix(suffix) {
                return code
            }
            return indicators[.file]
        }
        return indicators[.normal]
    }

    /// Wrap `text` with the SGR code, escaping into the standard
    /// `\e[<code>m…\e[0m` shape. Returns `text` untouched when `code`
    /// is empty (a no-op rule).
    public func wrap(_ text: String, with code: String) -> String {
        if code.isEmpty { return text }
        return "\u{1B}[\(code)m" + text + resetEscape
    }

    /// Fallback `LS_COLORS` used when neither env var is populated.
    /// Mirrors the original fixed palette in `Printer.colorize` so
    /// existing tests / users see the same output without LS_COLORS in
    /// their environment, plus a handful of extra type tones.
    static let defaultSpec = [
        "rs=0",
        "di=01;34",      // directory — bold blue
        "ln=01;36",      // symlink — bold cyan
        "pi=33",         // pipe — yellow
        "so=01;35",      // socket — bold magenta
        "bd=33;01",      // block device — bold yellow
        "cd=33;01",      // char device — bold yellow
        "or=40;31;01",   // orphan symlink — bold red on black
        "su=37;41",      // setuid — white on red
        "sg=30;43",      // setgid — black on yellow
        "tw=30;42",      // sticky, other-writable — black on green
        "ow=34;42",      // other-writable — blue on green
        "st=37;44",      // sticky — white on blue
        "ex=01;32",      // executable — bold green
    ].joined(separator: ":")
}
