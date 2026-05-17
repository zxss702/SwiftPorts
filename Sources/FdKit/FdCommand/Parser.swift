import Foundation
import FdKit
import ForgeKit
import RipgrepKit
import ShellKit

/// argv parser for `fd`. Hand-rolled for the same reasons RipgrepKit's
/// parser is: flags can be interleaved with positionals, several short
/// flags take attached or detached values, and a few flags
/// (`-e EXT`, `-E PATTERN`, `-t TYPE`, `-S SIZE`) are repeatable.
enum Parser {

    /// Output of a successful parse.
    struct ParsedArgs {
        var config: Fd.Configuration = Fd.Configuration()
        var paths: [String] = []
        var specialMode: SpecialMode = .none
    }

    enum SpecialMode {
        case none
        case help
        case version
    }

    struct ArgError: Error {
        let message: String
    }

    static func parse(_ argv: [String]) throws -> ParsedArgs {
        var out = ParsedArgs()
        // Qualify with the module name — RipgrepKit also exports a
        // `PatternOptions` / `PrinterOptions`, and importing both kits
        // here would leave the bare names ambiguous.
        var pat = FdKit.PatternOptions()
        var filter = FdKit.FilterOptions()
        var walker = Fd.defaultWalkerOptions()
        var printer = FdKit.PrinterOptions()
        var color: ColorChoice = .auto
        var positionals: [String] = []
        // `--search-path` values live outside the generic positional
        // list. If we threw them in with positionals, the
        // "first positional is the pattern" rule would consume them
        // as PATTERN and lose the user's intended root.
        var explicitSearchPaths: [String] = []

        var i = 0
        var doubleDashSeen = false

        // -- helpers --------------------------------------------

        func require(_ flag: String, _ value: String?) throws -> String {
            if let v = value, !v.isEmpty { return v }
            throw ArgError(message: "missing value for \(flag)")
        }

        func parseInt(_ flag: String, _ v: String) throws -> Int {
            guard let n = Int(v) else {
                throw ArgError(message: "\(flag) requires an integer (got '\(v)')")
            }
            return n
        }

        func parseFileType(_ raw: String) throws -> FilterOptions.FileType {
            switch raw {
            case "f", "file":                  return .file
            case "d", "directory", "dir":      return .directory
            case "l", "symlink":               return .symlink
            case "x", "executable":            return .executable
            case "e", "empty":                 return .empty
            case "s", "socket":                return .socket
            case "p", "pipe":                  return .pipe
            case "b", "block-device":          return .blockDevice
            case "c", "char-device":           return .charDevice
            default:
                throw ArgError(message: "unknown --type value '\(raw)'")
            }
        }

        // -- main loop ------------------------------------------

        while i < argv.count {
            let raw = argv[i]
            if doubleDashSeen {
                positionals.append(raw)
                i += 1
                continue
            }
            if raw == "--" {
                doubleDashSeen = true
                i += 1
                continue
            }

            // Long flags ---------------------------------------
            if raw.hasPrefix("--") {
                let body = String(raw.dropFirst(2))
                let (name, value): (String, String?) = {
                    if let eq = body.firstIndex(of: "=") {
                        return (String(body[..<eq]),
                                String(body[body.index(after: eq)...]))
                    }
                    return (body, nil)
                }()

                switch name {
                case "help":
                    out.specialMode = .help; return out
                case "version":
                    out.specialMode = .version; return out

                // Pattern syntax -----------------------------------
                case "glob":
                    pat.syntax = .glob
                    i += 1; continue
                case "regex":
                    pat.syntax = .regex
                    i += 1; continue
                case "fixed-strings":
                    pat.syntax = .fixedString
                    i += 1; continue
                case "full-path":
                    pat.matchFullPath = true
                    i += 1; continue
                case "ignore-case":
                    pat.caseMode = .ignoreCase
                    i += 1; continue
                case "case-sensitive":
                    pat.caseMode = .caseSensitive
                    i += 1; continue
                case "smart-case":
                    pat.caseMode = .smartCase
                    i += 1; continue

                // Repeatable filters -------------------------------
                case "extension":
                    let v = try value ?? takeValue(argv, &i)
                    pat.extensions.append(try require("--extension", v))
                    i += 1; continue
                case "type":
                    let v = try value ?? takeValue(argv, &i)
                    filter.fileTypes.insert(try parseFileType(
                        try require("--type", v)))
                    i += 1; continue
                case "exclude":
                    let v = try value ?? takeValue(argv, &i)
                    filter.excludePatterns.append(try require("--exclude", v))
                    i += 1; continue
                case "size":
                    let v = try value ?? takeValue(argv, &i)
                    filter.sizeConstraints.append(try parseSizeConstraint(
                        try require("--size", v)))
                    i += 1; continue
                case "changed-within", "change-newer-than", "newer":
                    let v = try value ?? takeValue(argv, &i)
                    filter.changedWithin = try parseDuration(try require("--changed-within", v))
                    i += 1; continue
                case "changed-before", "change-older-than", "older":
                    let v = try value ?? takeValue(argv, &i)
                    filter.changedBefore = try parseDuration(try require("--changed-before", v))
                    i += 1; continue

                // Depth -------------------------------------------
                case "max-depth", "maxdepth":
                    let v = try value ?? takeValue(argv, &i)
                    walker.maxDepth = try parseInt("--max-depth",
                                                   require("--max-depth", v))
                    i += 1; continue
                case "min-depth":
                    let v = try value ?? takeValue(argv, &i)
                    filter.minDepth = try parseInt("--min-depth",
                                                   require("--min-depth", v))
                    i += 1; continue
                case "exact-depth":
                    let v = try value ?? takeValue(argv, &i)
                    let n = try parseInt("--exact-depth",
                                         require("--exact-depth", v))
                    walker.maxDepth = n
                    filter.minDepth = n
                    i += 1; continue

                // Result cap --------------------------------------
                case "max-results":
                    let v = try value ?? takeValue(argv, &i)
                    filter.maxResults = try parseInt("--max-results",
                                                     require("--max-results", v))
                    i += 1; continue

                // Walker behaviour --------------------------------
                case "hidden":
                    walker.hidden = true
                    i += 1; continue
                case "no-hidden":
                    walker.hidden = false
                    i += 1; continue
                case "follow":
                    walker.followLinks = true
                    i += 1; continue
                case "one-file-system":
                    walker.oneFileSystem = true
                    i += 1; continue
                case "no-ignore":
                    walker.respectGitignore = false
                    walker.respectDotIgnore = false
                    walker.respectExclude = false
                    walker.respectParentIgnore = false
                    walker.respectGlobalIgnore = false
                    i += 1; continue
                case "no-ignore-vcs":
                    walker.respectGitignore = false
                    i += 1; continue
                case "no-ignore-parent":
                    walker.respectParentIgnore = false
                    i += 1; continue
                case "no-global-ignore-file":
                    walker.respectGlobalIgnore = false
                    i += 1; continue
                case "no-require-git":
                    walker.requireGit = false
                    i += 1; continue
                case "unrestricted":
                    walker.hidden = true
                    walker.respectGitignore = false
                    walker.respectDotIgnore = false
                    walker.respectExclude = false
                    walker.respectParentIgnore = false
                    walker.respectGlobalIgnore = false
                    i += 1; continue
                case "ignore-file":
                    let v = try value ?? takeValue(argv, &i)
                    let p = try require("--ignore-file", v)
                    walker.extraIgnoreFiles.append(Shell.resolve(p))
                    i += 1; continue

                // Output ------------------------------------------
                case "absolute-path":
                    printer.absolutePath = true
                    i += 1; continue
                case "relative-path":
                    printer.absolutePath = false
                    i += 1; continue
                case "strip-cwd-prefix":
                    printer.stripCwdPrefix = true
                    i += 1; continue
                case "print0":
                    printer.print0 = true
                    i += 1; continue
                case "path-separator":
                    let v = try value ?? takeValue(argv, &i)
                    printer.pathSeparator = try require("--path-separator", v)
                    i += 1; continue
                case "color":
                    // Accept both `--color=when` and `--color when`.
                    // Reject unknown values so typos surface as
                    // argument errors instead of silently picking
                    // `.auto`.
                    let v = try require("--color",
                                        value ?? takeValue(argv, &i))
                    guard let parsed = ColorChoice(argument: v) else {
                        throw ArgError(
                            message: "invalid --color value '\(v)' (expected auto / always / never)")
                    }
                    color = parsed
                    i += 1; continue
                case "no-color":
                    color = .never
                    i += 1; continue
                case "quiet":
                    printer.quiet = true
                    i += 1; continue

                // Thread / pacing knobs accepted for parity --------
                case "threads":
                    let v = try value ?? takeValue(argv, &i)
                    _ = try parseInt("--threads", require("--threads", v))
                    i += 1; continue
                case "search-path":
                    let v = try value ?? takeValue(argv, &i)
                    explicitSearchPaths.append(try require("--search-path", v))
                    i += 1; continue
                case "show-errors", "no-show-errors", "prune",
                     "no-config", "list-details", "owner", "no-owner",
                     "color-path", "no-prune":
                    // Accepted for parity, not yet wired.
                    i += 1; continue

                default:
                    throw ArgError(message: "unrecognized flag: \(raw)")
                }
            }

            // Short flags --------------------------------------
            if raw.hasPrefix("-"), raw.count >= 2, !raw.hasPrefix("--") {
                // `-1` is fd's alias for `--max-results=1`.
                if raw == "-1" {
                    filter.maxResults = 1
                    i += 1; continue
                }

                let body = raw.dropFirst()

                // Letters that take a value (attached or detached).
                let valueLetters: Set<Character> = [
                    "e", "E", "t", "S", "d",
                ]

                let chars = Array(body)
                var consumed = false
                var idx = 0
                while idx < chars.count {
                    let c = chars[idx]
                    if valueLetters.contains(c) {
                        var value: String?
                        if idx + 1 < chars.count {
                            value = String(chars[(idx + 1)...])
                        } else {
                            value = try takeValue(argv, &i)
                        }
                        switch c {
                        case "e":
                            pat.extensions.append(try require("-e", value))
                        case "E":
                            filter.excludePatterns.append(try require("-E", value))
                        case "t":
                            filter.fileTypes.insert(try parseFileType(
                                try require("-t", value)))
                        case "S":
                            filter.sizeConstraints.append(
                                try parseSizeConstraint(try require("-S", value)))
                        case "d":
                            walker.maxDepth = try parseInt(
                                "-d", require("-d", value))
                        default:
                            throw ArgError(message: "internal: unhandled value-letter -\(c)")
                        }
                        consumed = true
                        idx = chars.count
                        i += 1
                        continue
                    }
                    // Boolean shorts. Multiple in a row: `-Hu`.
                    switch c {
                    case "h":
                        out.specialMode = .help; return out
                    case "V":
                        out.specialMode = .version; return out
                    case "H": walker.hidden = true
                    case "I":
                        // Long form is `--no-ignore`. fd ships `-I` as a
                        // shortcut for the all-on-disabling family.
                        walker.respectGitignore = false
                        walker.respectDotIgnore = false
                        walker.respectExclude = false
                        walker.respectParentIgnore = false
                        walker.respectGlobalIgnore = false
                    case "u":
                        // `-u` is one level — `-uu` two, `-uuu` three.
                        // fd treats `-u` as `--no-ignore`, `-uu` as
                        // `--no-ignore --hidden`. Implemented per-`u`
                        // additively: every `u` toggles one more thing.
                        if walker.respectGitignore {
                            walker.respectGitignore = false
                            walker.respectDotIgnore = false
                            walker.respectExclude = false
                            walker.respectParentIgnore = false
                            walker.respectGlobalIgnore = false
                        } else if !walker.hidden {
                            walker.hidden = true
                        }
                    case "i": pat.caseMode = .ignoreCase
                    case "s": pat.caseMode = .caseSensitive
                    case "p": pat.matchFullPath = true
                    case "g":
                        // No-op: fd has dropped `-g` for `--glob` in
                        // recent versions. Accepted for parity.
                        pat.syntax = .glob
                    case "F": pat.syntax = .fixedString
                    case "a": printer.absolutePath = true
                    case "L": walker.followLinks = true
                    case "0": printer.print0 = true
                    case "q": printer.quiet = true
                    case "l":
                        // --list-details — accepted for parity but
                        // the engine emits the plain path form.
                        break
                    case "j":
                        // Thread count short form; consume a value.
                        if idx + 1 < chars.count {
                            _ = try parseInt("-j",
                                require("-j", String(chars[(idx + 1)...])))
                            idx = chars.count - 1
                        } else {
                            let v = try takeValue(argv, &i)
                            _ = try parseInt("-j", require("-j", v))
                        }
                    default:
                        throw ArgError(message: "unrecognized short flag: -\(c)")
                    }
                    idx += 1
                }
                if !consumed { i += 1 }
                continue
            }

            // Positional --------------------------------------
            positionals.append(raw)
            i += 1
        }

        // First positional → pattern (if no prior pattern was set).
        // Everything after → search paths. `--search-path` entries are
        // appended afterwards so they always act as roots, even when
        // no pattern was supplied at all.
        if !positionals.isEmpty {
            pat.pattern = positionals.first!
            out.paths = Array(positionals.dropFirst())
        }
        out.paths.append(contentsOf: explicitSearchPaths)

        out.config.pattern = pat
        out.config.filter = filter
        out.config.walker = walker
        out.config.printer = printer
        out.config.printer.color = color.resolved()
        return out
    }

    // MARK: - Small helpers ---------------------------------------

    private static func takeValue(_ argv: [String], _ i: inout Int) throws -> String? {
        if i + 1 < argv.count {
            i += 1
            return argv[i]
        }
        return nil
    }

    /// Parse fd's `--size` spec: an optional `+` or `-` sign followed
    /// by digits and an optional suffix (`b`, `k`/`ki`, `m`/`mi`,
    /// `g`/`gi`, `t`/`ti`). The suffix without `i` is powers-of-10;
    /// with `i` is powers-of-2. fd accepts both.
    ///
    /// Sign semantics — mirrors what upstream fd documents:
    ///   * `+N` → file size must be at least N.
    ///   * `-N` → file size must be at most N.
    ///   * `N`  → file size must be exactly N. (The previous default
    ///     was `.atLeast`, which silently broadened scripts that
    ///     wanted exact-size filtering.)
    private static func parseSizeConstraint(_ raw: String) throws
    -> FilterOptions.SizeConstraint {
        var s = raw
        var dir: FilterOptions.SizeConstraint.Direction = .exactly
        if s.hasPrefix("+") {
            dir = .atLeast
            s.removeFirst()
        } else if s.hasPrefix("-") {
            dir = .atMost
            s.removeFirst()
        }
        // Split into digits and suffix.
        var digits = ""
        var suffix = ""
        for ch in s {
            if ch.isNumber {
                digits.append(ch)
            } else {
                suffix.append(ch)
            }
        }
        guard let n = UInt64(digits) else {
            throw ArgError(message: "invalid --size value '\(raw)'")
        }
        let multiplier: UInt64
        switch suffix.lowercased() {
        case "", "b":                  multiplier = 1
        case "k":                      multiplier = 1_000
        case "ki":                     multiplier = 1 << 10
        case "m":                      multiplier = 1_000_000
        case "mi":                     multiplier = 1 << 20
        case "g":                      multiplier = 1_000_000_000
        case "gi":                     multiplier = 1 << 30
        case "t":                      multiplier = 1_000_000_000_000
        case "ti":                     multiplier = 1 << 40
        default:
            throw ArgError(message: "unknown --size suffix '\(suffix)'")
        }
        return FilterOptions.SizeConstraint(direction: dir,
                                            bytes: n * multiplier)
    }

    /// fd's duration syntax accepts a small grab-bag — `1h`, `30min`,
    /// `90s`, `2d`, `1weeks`, ISO `2024-01-01T12:00:00` — but the most
    /// common spellings are short suffixed durations. Implement those.
    /// Returns seconds.
    private static func parseDuration(_ raw: String) throws -> TimeInterval {
        let lower = raw.lowercased()
        let suffixes: [(String, Double)] = [
            ("seconds", 1), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1),
            ("minutes", 60), ("minute", 60), ("mins", 60), ("min", 60), ("m", 60),
            ("hours", 3600), ("hour", 3600), ("hrs", 3600), ("hr", 3600), ("h", 3600),
            ("days", 86_400), ("day", 86_400), ("d", 86_400),
            ("weeks", 86_400 * 7), ("week", 86_400 * 7), ("w", 86_400 * 7),
        ]
        for (suffix, scale) in suffixes where lower.hasSuffix(suffix) {
            let head = String(lower.dropLast(suffix.count))
            if let n = Double(head) {
                return n * scale
            }
        }
        // Bare seconds form.
        if let n = Double(lower) { return n }
        throw ArgError(message: "invalid duration '\(raw)'")
    }

    static let helpText: String = """
fd [OPTIONS] [PATTERN] [PATH ...]

Pure-Swift port of sharkdp/fd. List files (and directories) under PATH
whose names match PATTERN. PATTERN is a regex by default; use `--glob`
for shell-style globs or `--fixed-strings` for literal substrings.
Respects .gitignore, .ignore, .fdignore. Skips hidden files by default.

OPTIONS

  -H, --hidden              Include hidden files / directories.
  -I, --no-ignore           Don't read any ignore files.
      --no-ignore-vcs       Don't read .gitignore.
      --no-ignore-parent    Don't walk parent dirs for ignore files.
      --no-global-ignore-file
                            Don't read the user's global git ignore.
      --no-require-git      Apply .gitignore even outside a git repo.
      --ignore-file=PATH    Add PATH as an extra ignore file.
  -u, --unrestricted        Alias for --no-ignore (repeatable: -uu adds
                            --hidden).
  -s, --case-sensitive      Force case-sensitive matching.
  -i, --ignore-case         Case-insensitive matching.
      --smart-case          Insensitive unless PATTERN has uppercase.
  -g, --glob                Treat PATTERN as a shell glob.
      --regex               Treat PATTERN as a regex (default).
  -F, --fixed-strings       Treat PATTERN as a literal substring.
  -p, --full-path           Match against the whole path, not basename.

  -e, --extension=EXT       Filter by extension (repeatable).
  -t, --type=TYPE           Filter by type. f|d|l|x|e|s|p|b|c.
  -E, --exclude=PATTERN     Exclude paths matching glob (repeatable).
  -S, --size=SPEC           Filter by size (e.g. `+1M`, `-100k`,
                            repeatable).
      --changed-within=TIME Only include entries modified within TIME.
      --changed-before=TIME Only include entries modified before TIME.

  -d, --max-depth=N         Limit traversal depth.
      --min-depth=N         Require minimum depth.
      --exact-depth=N       Equivalent to --max-depth=N --min-depth=N.
      --max-results=N       Stop after N entries.
  -1                        Alias for --max-results=1.
  -L, --follow              Follow symlinks.
      --one-file-system     Stay on the starting filesystem.

  -a, --absolute-path       Print absolute paths.
      --relative-path       Print paths relative to the cwd (default).
      --strip-cwd-prefix    Strip leading `./` from output.
      --path-separator=SEP  Replace `/` with SEP in printed paths.
  -0, --print0              Terminate output with NUL.
      --color=WHEN          auto / always / never.

  -q, --quiet               No output; signal via exit code.
  -h, --help                Show this help.
  -V, --version             Show version and exit.

EXIT STATUS

  0  At least one entry matched.
  1  No entries matched.
  2  An error occurred.
"""
}
