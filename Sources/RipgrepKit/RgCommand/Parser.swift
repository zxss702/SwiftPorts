import Foundation
import ForgeKit
import RipgrepKit
import ShellKit

/// argv parser for `rg`. Hand-rolled (as opposed to ArgumentParser
/// `@Option`/`@Flag`) because:
///
///   * ripgrep accepts flags anywhere on the command line, mixed
///     freely with positional patterns and paths.
///   * Several flags (`-A 3` / `-A3`) accept fused / spaced forms
///     interchangeably.
///   * `-e`/`--regexp` and `-f`/`--file` are repeatable and change
///     positional argument semantics (after the first `-e`, all
///     positionals are paths).
///
/// Parsing is two-pass: first split each token into either a flag-with-
/// value or a positional; then resolve positional ownership based on
/// the flag context.
enum Parser {

    /// Output of a successful parse.
    struct ParsedArgs {
        var config: Ripgrep.Configuration = Ripgrep.Configuration()
        var paths: [String] = []
        var specialMode: SpecialMode = .none
    }

    enum SpecialMode {
        case none
        case help
        case version
        case typeList
        case files
    }

    struct ArgError: Error {
        let message: String
    }

    static func parse(_ argv: [String]) throws -> ParsedArgs {
        var out = ParsedArgs()
        // Track multi-pattern mode — `-e` or `-f` swaps the positional
        // role from "first positional = pattern" to "all positionals
        // are paths".
        var patternsSet: [String] = []
        var positionals: [String] = []

        // Mutable copies of the sub-options we hand back via
        // `out.config`. Mutating fields on a struct held in a property
        // chain (`out.config.pattern.patterns.append(...)`) is fine
        // but more readable with locals.
        var pat = PatternOptions()
        var search = SearchOptions()
        var walker = WalkerOptions()
        var printer = PrinterOptions()
        var outputMode: Ripgrep.OutputMode = .standard
        var patternsAreExplicit = false

        var i = 0
        var doubleDashSeen = false
        var color: ColorChoice = .auto

        // Helpers --------------------------------------------------

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

        func parseSize(_ flag: String, _ v: String) throws -> Int {
            // Accept K/M/G suffix.
            let lower = v.lowercased()
            var multiplier = 1
            var digits = lower
            if let last = lower.last, "kmg".contains(last) {
                digits = String(lower.dropLast())
                switch last {
                case "k": multiplier = 1024
                case "m": multiplier = 1024 * 1024
                case "g": multiplier = 1024 * 1024 * 1024
                default: break
                }
            }
            guard let n = Int(digits) else {
                throw ArgError(message: "\(flag) requires NUM[K|M|G] (got '\(v)')")
            }
            return n * multiplier
        }

        // ----------------------------------------------------------

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

            // Long flags ------------------------------------------------
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
                case "type-list":
                    out.specialMode = .typeList; return out
                case "files":
                    out.specialMode = .files; i += 1; continue
                case "no-config":
                    // We don't read user config files; nothing to do.
                    i += 1; continue
                case "regexp":
                    let v = try value ?? takeValue(argv, &i)
                    patternsSet.append(try require("--regexp", v))
                    patternsAreExplicit = true
                    i += 1; continue
                case "file":
                    let v = try value ?? takeValue(argv, &i)
                    let path = try require("--file", v)
                    try loadPatternFile(path, into: &patternsSet)
                    patternsAreExplicit = true
                    i += 1; continue
                case "fixed-strings":
                    pat.fixedStrings = true; i += 1; continue
                case "no-fixed-strings":
                    pat.fixedStrings = false; i += 1; continue
                case "ignore-case":
                    pat.caseMode = .ignoreCase; i += 1; continue
                case "smart-case":
                    pat.caseMode = .smartCase; i += 1; continue
                case "case-sensitive":
                    pat.caseMode = .caseSensitive; i += 1; continue
                case "word-regexp":
                    pat.wordRegexp = true; i += 1; continue
                case "line-regexp":
                    pat.lineRegexp = true; i += 1; continue
                case "invert-match":
                    pat.invertMatch = true; i += 1; continue
                case "multiline":
                    pat.multiline = true; i += 1; continue
                case "no-multiline":
                    pat.multiline = false; i += 1; continue
                case "multiline-dotall":
                    pat.multilineDotall = true; i += 1; continue
                case "crlf":
                    search.crlf = true; i += 1; continue
                case "null-data":
                    search.nullData = true; i += 1; continue
                case "text":
                    search.binaryAsText = true; i += 1; continue
                case "binary":
                    search.searchBinary = true; i += 1; continue
                case "stop-on-nonmatch":
                    search.stopOnNonmatch = true; i += 1; continue
                case "encoding":
                    let v = try value ?? takeValue(argv, &i)
                    let raw = try require("--encoding", v)
                    search.encoding = parseEncoding(raw)
                    i += 1; continue
                case "max-count":
                    let v = try value ?? takeValue(argv, &i)
                    search.maxCount = try parseInt("--max-count", require("--max-count", v))
                    i += 1; continue
                case "max-depth", "maxdepth":
                    let v = try value ?? takeValue(argv, &i)
                    walker.maxDepth = try parseInt("--max-depth", require("--max-depth", v))
                    i += 1; continue
                case "max-filesize":
                    let v = try value ?? takeValue(argv, &i)
                    walker.maxFilesize = try parseSize("--max-filesize", require("--max-filesize", v))
                    i += 1; continue
                case "max-columns":
                    let v = try value ?? takeValue(argv, &i)
                    printer.maxColumns = try parseInt("--max-columns", require("--max-columns", v))
                    i += 1; continue
                case "max-columns-preview":
                    printer.maxColumnsPreview = true; i += 1; continue
                case "after-context":
                    let v = try value ?? takeValue(argv, &i)
                    search.afterContext = try parseInt("--after-context", require("--after-context", v))
                    i += 1; continue
                case "before-context":
                    let v = try value ?? takeValue(argv, &i)
                    search.beforeContext = try parseInt("--before-context", require("--before-context", v))
                    i += 1; continue
                case "context":
                    let v = try value ?? takeValue(argv, &i)
                    let n = try parseInt("--context", require("--context", v))
                    search.afterContext = n
                    search.beforeContext = n
                    i += 1; continue
                case "context-separator":
                    let v = try value ?? takeValue(argv, &i)
                    printer.contextSeparator = try require("--context-separator", v)
                    i += 1; continue
                case "field-context-separator":
                    let v = try value ?? takeValue(argv, &i)
                    printer.contextFieldSeparator = try require("--field-context-separator", v)
                    i += 1; continue
                case "field-match-separator":
                    let v = try value ?? takeValue(argv, &i)
                    printer.matchFieldSeparator = try require("--field-match-separator", v)
                    i += 1; continue
                case "hidden":
                    walker.hidden = true; i += 1; continue
                case "no-hidden":
                    walker.hidden = false; i += 1; continue
                case "follow":
                    walker.followLinks = true; i += 1; continue
                case "no-follow":
                    walker.followLinks = false; i += 1; continue
                case "one-file-system":
                    walker.oneFileSystem = true; i += 1; continue
                case "no-ignore":
                    walker.respectGitignore = false
                    walker.respectDotIgnore = false
                    walker.respectExclude = false
                    walker.respectParentIgnore = false
                    walker.respectGlobalIgnore = false
                    i += 1; continue
                case "no-ignore-vcs":
                    walker.respectGitignore = false; i += 1; continue
                case "no-ignore-dot":
                    walker.respectDotIgnore = false; i += 1; continue
                case "no-ignore-exclude":
                    walker.respectExclude = false; i += 1; continue
                case "no-ignore-parent":
                    walker.respectParentIgnore = false; i += 1; continue
                case "no-ignore-global":
                    walker.respectGlobalIgnore = false; i += 1; continue
                case "no-ignore-files", "no-require-git", "no-ignore-messages":
                    // Accepted for parity; not yet wired.
                    i += 1; continue
                case "ignore-file":
                    let v = try value ?? takeValue(argv, &i)
                    let p = try require("--ignore-file", v)
                    walker.extraIgnoreFiles.append(Shell.resolve(p))
                    i += 1; continue
                case "glob":
                    let v = try value ?? takeValue(argv, &i)
                    walker.globs.append(try require("--glob", v))
                    i += 1; continue
                case "iglob":
                    let v = try value ?? takeValue(argv, &i)
                    walker.globs.append(try require("--iglob", v))
                    walker.globsCaseInsensitive = true
                    i += 1; continue
                case "glob-case-insensitive":
                    walker.globsCaseInsensitive = true; i += 1; continue
                case "type":
                    let v = try value ?? takeValue(argv, &i)
                    walker.includeTypes.append(try require("--type", v))
                    i += 1; continue
                case "type-not":
                    let v = try value ?? takeValue(argv, &i)
                    walker.excludeTypes.append(try require("--type-not", v))
                    i += 1; continue
                case "type-add":
                    let v = try value ?? takeValue(argv, &i)
                    try walker.typeRegistry.add(try require("--type-add", v))
                    i += 1; continue
                case "type-clear":
                    let v = try value ?? takeValue(argv, &i)
                    walker.typeRegistry.clear(try require("--type-clear", v))
                    i += 1; continue
                case "with-filename":
                    printer.withFilename = true; i += 1; continue
                case "no-filename":
                    printer.withFilename = false; i += 1; continue
                case "line-number":
                    printer.lineNumber = true; i += 1; continue
                case "no-line-number":
                    printer.lineNumber = false; i += 1; continue
                case "column":
                    printer.column = true
                    printer.lineNumber = true
                    i += 1; continue
                case "no-column":
                    printer.column = false; i += 1; continue
                case "byte-offset":
                    printer.byteOffset = true; i += 1; continue
                case "heading":
                    printer.heading = true; i += 1; continue
                case "no-heading":
                    printer.heading = false; i += 1; continue
                case "pretty":
                    printer.heading = true
                    printer.lineNumber = true
                    color = .always
                    i += 1; continue
                case "quiet":
                    printer.quiet = true; i += 1; continue
                case "null":
                    printer.nullSeparator = true; i += 1; continue
                case "only-matching":
                    printer.onlyMatching = true; i += 1; continue
                case "passthru", "passthrough":
                    printer.passthru = true; i += 1; continue
                case "replace":
                    let v = try value ?? takeValue(argv, &i)
                    printer.replace = try require("--replace", v)
                    i += 1; continue
                case "trim":
                    printer.trim = true; i += 1; continue
                case "path-separator":
                    let v = try value ?? takeValue(argv, &i)
                    printer.pathSeparator = try require("--path-separator", v)
                    i += 1; continue
                case "include-zero":
                    printer.includeZero = true; i += 1; continue
                case "color":
                    let v = value ?? "always"
                    color = ColorChoice(argument: v) ?? .auto
                    i += 1; continue
                case "no-color":
                    color = .never; i += 1; continue
                case "colors":
                    let v = try value ?? takeValue(argv, &i)
                    try applyColors(spec: require("--colors", v),
                                    into: &printer.colorSpec)
                    i += 1; continue
                case "vimgrep":
                    printer.heading = false
                    printer.lineNumber = true
                    printer.column = true
                    printer.withFilename = true
                    i += 1; continue
                case "count":
                    outputMode = .summary(.count); i += 1; continue
                case "count-matches":
                    outputMode = .summary(.countMatches); i += 1; continue
                case "files-with-matches":
                    outputMode = .summary(.filesWithMatches); i += 1; continue
                case "files-without-match":
                    outputMode = .summary(.filesWithoutMatch); i += 1; continue
                case "json":
                    outputMode = .json; i += 1; continue
                case "no-json":
                    outputMode = .standard; i += 1; continue
                case "stats":
                    // Stats lines aren't emitted yet — accepted for parity.
                    i += 1; continue
                case "block-buffered", "line-buffered", "mmap",
                     "no-mmap", "no-unicode", "unicode", "search-zip",
                     "no-search-zip", "debug", "trace", "no-messages",
                     "sort-files", "auto-hybrid-regex", "no-pcre2-unicode",
                     "pcre2", "no-pcre2", "no-encoding":
                    // Accepted but not yet implemented.
                    i += 1; continue
                default:
                    throw ArgError(message: "unrecognized flag: \(raw)")
                }
            }

            // Short flags ----------------------------------------------
            if raw.hasPrefix("-"), raw.count >= 2, !raw.hasPrefix("--") {
                // Numeric-only `-3` is an alias for `-C 3`.
                let body = raw.dropFirst()
                if body.allSatisfy({ $0.isNumber }) {
                    if let n = Int(body) {
                        search.beforeContext = n
                        search.afterContext = n
                        i += 1
                        continue
                    }
                }

                // Handle short-with-attached-value where appropriate
                // before falling into the per-char loop. The set of
                // "takes a value" short flags is small.
                let valueLetters: Set<Character> = [
                    "e", "f", "g", "t", "T", "A", "B", "C", "m", "d",
                    "M", "r", "E", "j",
                ]

                let chars = Array(body)
                var consumed = false
                var idx = 0
                while idx < chars.count {
                    let c = chars[idx]
                    if valueLetters.contains(c) {
                        // Attached value: `-A3`, `-eFOO`. Otherwise pull
                        // the next argv.
                        var value: String?
                        if idx + 1 < chars.count {
                            value = String(chars[(idx + 1)...])
                        } else {
                            value = try takeValue(argv, &i)
                        }
                        switch c {
                        case "e":
                            patternsSet.append(try require("-e", value))
                            patternsAreExplicit = true
                        case "f":
                            try loadPatternFile(try require("-f", value),
                                                into: &patternsSet)
                            patternsAreExplicit = true
                        case "g":
                            walker.globs.append(try require("-g", value))
                        case "t":
                            walker.includeTypes.append(try require("-t", value))
                        case "T":
                            walker.excludeTypes.append(try require("-T", value))
                        case "A":
                            search.afterContext = try parseInt("-A", require("-A", value))
                        case "B":
                            search.beforeContext = try parseInt("-B", require("-B", value))
                        case "C":
                            let n = try parseInt("-C", require("-C", value))
                            search.afterContext = n
                            search.beforeContext = n
                        case "m":
                            search.maxCount = try parseInt("-m", require("-m", value))
                        case "d":
                            walker.maxDepth = try parseInt("-d", require("-d", value))
                        case "M":
                            printer.maxColumns = try parseInt("-M", require("-M", value))
                        case "r":
                            printer.replace = try require("-r", value)
                        case "E":
                            search.encoding = parseEncoding(try require("-E", value))
                        case "j":
                            _ = try parseInt("-j", require("-j", value))
                            // Thread count accepted; we run single-threaded.
                        default:
                            throw ArgError(message: "internal: unhandled value-letter -\(c)")
                        }
                        consumed = true
                        idx = chars.count
                        i += 1
                        continue
                    }
                    // Boolean shorts. Multiple in a row: `-iv`.
                    switch c {
                    case "h":
                        out.specialMode = .help; return out
                    case "V":
                        out.specialMode = .version; return out
                    case "i": pat.caseMode = .ignoreCase
                    case "s": pat.caseMode = .caseSensitive
                    case "S": pat.caseMode = .smartCase
                    case "F": pat.fixedStrings = true
                    case "w": pat.wordRegexp = true
                    case "x": pat.lineRegexp = true
                    case "v": pat.invertMatch = true
                    case "U": pat.multiline = true
                    case "a": search.binaryAsText = true
                    case "n": printer.lineNumber = true
                    case "N": printer.lineNumber = false
                    case "H": printer.withFilename = true
                    case "I": printer.withFilename = false
                    case "b": printer.byteOffset = true
                    case "o": printer.onlyMatching = true
                    case "q": printer.quiet = true
                    case "L": walker.followLinks = true
                    case "p": printer.heading = true
                              printer.lineNumber = true
                              color = .always
                    case "u": walker.hidden = true
                    case "c":
                        outputMode = .summary(.count)
                    case "l":
                        outputMode = .summary(.filesWithMatches)
                    case "z":
                        // --search-zip — not implemented.
                        break
                    case "0":
                        printer.nullSeparator = true
                    case ".":
                        walker.hidden = true
                    case "P":
                        // PCRE2 backend — fall back to NSRegularExpression.
                        break
                    default:
                        throw ArgError(message: "unrecognized short flag: -\(c)")
                    }
                    idx += 1
                }
                if !consumed { i += 1 }
                continue
            }

            // Positional ----------------------------------------------
            positionals.append(raw)
            i += 1
        }

        // Resolve positional ownership ---------------------------------
        // Pattern-less modes (`--files`, `--type-list`, `--help`,
        // `--version`) treat every positional as a path — there's no
        // pattern to consume.
        let modeWantsPattern: Bool = {
            switch out.specialMode {
            case .none:                          return true
            case .files, .typeList, .help, .version:
                                                 return false
            }
        }()
        if patternsAreExplicit || !modeWantsPattern {
            // All positionals are paths.
            out.paths = positionals
        } else {
            // First positional is the pattern, the rest are paths.
            if positionals.isEmpty {
                throw ArgError(message: "missing pattern")
            }
            patternsSet.append(positionals.first!)
            out.paths = Array(positionals.dropFirst())
        }

        pat.patterns = patternsSet
        out.config.pattern = pat
        out.config.search = search
        out.config.walker = walker
        out.config.printer = printer
        // Resolve color now that we've finished parsing.
        out.config.printer.color = color.resolved()
        out.config.output = outputMode
        return out
    }

    // MARK: - Small helpers

    private static func takeValue(_ argv: [String], _ i: inout Int) throws -> String? {
        if i + 1 < argv.count {
            i += 1
            return argv[i]
        }
        return nil
    }

    /// Read a pattern file (`-f PATH`). Empty lines match every line,
    /// blank lines included. `-` means stdin.
    private static func loadPatternFile(_ path: String,
                                        into out: inout [String]) throws {
        if path == "-" {
            let data = FileHandle.standardInput.availableData
            let text = String(decoding: data, as: UTF8.self)
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                out.append(String(raw))
            }
            return
        }
        let url = Shell.resolve(path)
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(raw)
            if s.hasSuffix("\r") { s.removeLast() }
            out.append(s)
        }
    }

    /// Map ripgrep's `--encoding` names onto Foundation encodings.
    private static func parseEncoding(_ raw: String) -> String.Encoding? {
        switch raw.lowercased() {
        case "utf-8", "utf8":  return .utf8
        case "utf-16le":       return .utf16LittleEndian
        case "utf-16be":       return .utf16BigEndian
        case "utf-16":         return .utf16
        case "ascii":          return .ascii
        case "iso-8859-1", "latin1", "latin-1":
                               return .isoLatin1
        case "iso-8859-2", "latin2", "latin-2":
                               return .isoLatin2
        case "windows-1252", "cp1252":
                               return .windowsCP1252
        case "macroman", "mac-roman":
                               return .macOSRoman
        case "none", "auto":   return nil
        default:               return nil
        }
    }

    /// Apply a `--colors=section:attr:value` spec to `colorSpec`.
    /// e.g. `path:fg:green`, `match:style:bold`, `line:bg:cyan`.
    private static func applyColors(spec: String,
                                    into out: inout ColorSpec) throws {
        let parts = spec.split(separator: ":", maxSplits: 2,
                               omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw ArgError(message: "invalid --colors spec: \(spec)")
        }
        let section = parts[0]
        let attr = parts[1]
        let value = parts[2]
        let code = ansiCode(attribute: String(attr), value: String(value))
        switch section {
        case "path":  out.path = code ?? out.path
        case "line":  out.lineNumber = code ?? out.lineNumber
        case "match": out.matched = code ?? out.matched
        case "column": break  // accepted, no-op
        default:
            throw ArgError(message: "unknown --colors section: \(section)")
        }
    }

    /// Translate `attr:value` into a raw ANSI escape sequence (or
    /// extends it). Only the subset that matters in practice — `fg:`,
    /// `bg:`, `style:bold`/`underline`/`intense`.
    private static func ansiCode(attribute: String, value: String) -> String? {
        if attribute == "style" {
            switch value {
            case "bold":      return "\u{1B}[1m"
            case "intense":   return "\u{1B}[1m"
            case "underline": return "\u{1B}[4m"
            case "italic":    return "\u{1B}[3m"
            case "nobold", "nointense", "nounderline", "noitalic":
                              return ""
            default:          return nil
            }
        }
        let base: Int
        switch attribute {
        case "fg": base = 30
        case "bg": base = 40
        default:   return nil
        }
        let table: [String: Int] = [
            "black": 0, "red": 1, "green": 2, "yellow": 3,
            "blue": 4, "magenta": 5, "cyan": 6, "white": 7,
        ]
        if let n = table[value.lowercased()] {
            return "\u{1B}[\(base + n)m"
        }
        // 256-color form: "fg:0xFF" / "fg:255".
        if let n = Int(value) {
            return "\u{1B}[\(base + 8);5;\(n)m"
        }
        return nil
    }

    static let helpText: String = """
rg [OPTIONS] PATTERN [PATH ...]

Pure-Swift port of BurntSushi/ripgrep. Recursively search the current
directory for lines matching a regex pattern. Respects .gitignore,
.ignore, and .rgignore. Skips hidden files / dirs and binary files by
default.

OPTIONS

  -e, --regexp=PAT          Add a pattern (repeatable).
  -f, --file=PATH           Read patterns from PATH (one per line).
  -F, --fixed-strings       Treat patterns as literal strings.
  -i, --ignore-case         Case-insensitive search.
  -S, --smart-case          Insensitive unless the pattern has uppercase.
  -s, --case-sensitive      Force case-sensitive (default).
  -w, --word-regexp         Require word boundaries around the match.
  -x, --line-regexp         Require the match to span the whole line.
  -v, --invert-match        Emit non-matching lines.
  -U, --multiline           Allow patterns to span newlines.
      --multiline-dotall    Make '.' match newlines in -U mode.
  -m, --max-count=N         Stop after N matches per file.
  -E, --encoding=ENC        Force a text encoding.
      --crlf                Treat CR/LF as line terminator.
      --null-data           Use NUL as line separator.

  -A, --after-context=N     Show N lines after each match.
  -B, --before-context=N    Show N lines before each match.
  -C, --context=N           Shortcut for -A N -B N.
      --stop-on-nonmatch    Stop a file scan on the first non-match.

  -t, --type=TYPE           Include files of TYPE.
  -T, --type-not=TYPE       Exclude files of TYPE.
      --type-add=SPEC       e.g. --type-add=foo:*.foo
      --type-clear=TYPE     Clear all globs for TYPE.
      --type-list           List default file types and exit.
  -g, --glob=GLOB           Include/exclude paths matching GLOB.
      --iglob=GLOB          Case-insensitive --glob.
      --hidden              Include hidden files / directories.
  -L, --follow              Follow symlinks.
      --max-depth=N         Limit recursion depth.
      --max-filesize=N      Skip files larger than N bytes.
      --no-ignore           Don't read any ignore files.
      --no-ignore-vcs       Don't read .gitignore.
      --no-ignore-dot       Don't read .ignore / .rgignore.
      --no-ignore-parent    Don't walk parent dirs for ignore files.
      --no-ignore-global    Don't read the user's global git ignore.
      --ignore-file=PATH    Add PATH as an extra ignore file.
      --one-file-system     Stay on the starting filesystem.

  -n, --line-number         Show 1-indexed line numbers.
  -N, --no-line-number      Hide line numbers.
  -H, --with-filename       Always print the filename.
  -I, --no-filename         Never print the filename.
      --column              Show 1-indexed column numbers.
  -b, --byte-offset         Show the byte offset of each match.
      --heading             Group hits under a file heading.
      --color=WHEN          auto / always / never.
      --colors=SPEC         Customize colors (`path:fg:green`, etc).
  -o, --only-matching       Print only the matched text.
  -r, --replace=TEXT        Substitute TEXT for each match.
  -p, --pretty              Headings + line numbers + color.
      --trim                Trim leading whitespace from output lines.
      --max-columns=N       Skip lines longer than N characters.
      --max-columns-preview Show "[..]" preview for skipped lines.
      --vimgrep             vimgrep-compatible output.
      --path-separator=SEP  Replace `/` with SEP in output paths.
  -0, --null                NUL-terminate filenames.

  -c, --count               Print count of matching lines per file.
      --count-matches       Print count of all submatches per file.
  -l, --files-with-matches  Print only matching filenames.
      --files-without-match Print only non-matching filenames.
      --files               Print every file that would be searched.
      --json                JSON Lines output (rg --json schema).
      --include-zero        Include zero-match files in summary modes.

  -q, --quiet               Suppress output; signal via exit code.
  -h, --help                Show this help.
  -V, --version             Show version and exit.

EXIT STATUS

  0  At least one match was found.
  1  No matches found.
  2  An error occurred (bad regex, IO failure, …).
"""
}
