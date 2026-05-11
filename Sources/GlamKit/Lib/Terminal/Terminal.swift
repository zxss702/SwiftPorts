import Foundation
import ForgeKit
import ShellKit

/// Terminal capability profile — used by the ANSI emitter to pick the
/// right escape sequences (truecolor SGR vs. 256-color SGR vs. ANSI-16
/// vs. plain text) and by the renderer to pick the right bundled
/// style when caller asks for `.auto`.
public struct Terminal: Sendable, Hashable {
    /// Whether any ANSI escape sequence should be emitted at all.
    /// `false` ⇒ honor `NO_COLOR`, non-TTY output, or `TERM=dumb`.
    public var colorEnabled: Bool

    /// 24-bit per-channel SGR (`38;2;r;g;b`) supported. Implies
    /// `eightBitColor`.
    public var trueColor: Bool

    /// 8-bit indexed SGR (`38;5;n`) supported. Implies 16-color.
    public var eightBitColor: Bool

    /// OSC 8 hyperlinks (`ESC ]8;;URL ESC \`) supported. We gate
    /// this on the same heuristic glamour uses — `TERM` contains
    /// `xterm` / `screen` / `tmux` / `alacritty` and `colorEnabled`.
    public var hyperlinks: Bool

    /// Terminal background hint: `.dark`, `.light`, `.none`. `.none`
    /// means the renderer should fall back to `notty` (no color at
    /// all). Computed from `COLORFGBG`, `GLAMOUR_STYLE`, and the
    /// `colorEnabled` gate — never blocks on an OSC 11 round-trip,
    /// since stdout might not even be a TTY.
    public var background: Background

    public enum Background: Sendable, Hashable {
        case dark, light, none
    }

    public init(colorEnabled: Bool,
                trueColor: Bool,
                eightBitColor: Bool,
                hyperlinks: Bool,
                background: Background) {
        self.colorEnabled  = colorEnabled
        self.trueColor     = trueColor
        self.eightBitColor = eightBitColor
        self.hyperlinks    = hyperlinks
        self.background    = background
    }

    /// Detected capability based on stdout. Mirrors what glab does in
    /// `getGlamourStyle` (termenv + `term.IsTerminal`) plus the
    /// `NO_COLOR` / `CLICOLOR_FORCE` env contract.
    public static var detected: Terminal {
        let isTTY = TTY.isStdoutTTY
        let term = Shell.env("TERM") ?? ""

        let noColor       = (Shell.env("NO_COLOR")?.isEmpty == false)
        let forceColor    = (Shell.env("CLICOLOR_FORCE").map { !$0.isEmpty && $0 != "0" } ?? false)
        let dumbTerm      = term == "dumb"
        // `colorEnabled` follows ForgeKit's TTY policy plus the
        // dumb-terminal escape hatch — glamour falls back to the
        // `notty` style in the same situations.
        let colorEnabled  = !noColor && !dumbTerm && (forceColor || isTTY)

        let colorterm     = (Shell.env("COLORTERM") ?? "").lowercased()
        let trueColor     = colorEnabled &&
            (colorterm == "truecolor" || colorterm == "24bit")
        let eightBitColor = colorEnabled &&
            (trueColor || term.contains("256color") || term.contains("256"))

        let hyperlinks    = colorEnabled && (
            term.hasPrefix("xterm") ||
            term.hasPrefix("screen") ||
            term.hasPrefix("tmux") ||
            term.hasPrefix("alacritty") ||
            term.hasPrefix("wezterm") ||
            term.hasPrefix("kitty") ||
            term.hasPrefix("ghostty")
        )

        let bg: Background
        if !colorEnabled {
            bg = .none
        } else if let s = Shell.env("GLAMOUR_STYLE")?.lowercased() {
            switch s {
            case "light": bg = .light
            case "notty", "ascii", "none": bg = .none
            default:      bg = .dark
            }
        } else {
            bg = guessBackground()
        }

        return Terminal(colorEnabled:  colorEnabled,
                        trueColor:     trueColor,
                        eightBitColor: eightBitColor,
                        hyperlinks:    hyperlinks,
                        background:    bg)
    }

    /// Cheap background guess — same idea as termenv's
    /// `HasDarkBackground` without the OSC 11 round-trip (which
    /// requires a controlling TTY and a synchronous read that we
    /// don't want blocking the renderer). We inspect `COLORFGBG`
    /// (a de-facto X11 env var that VTE-family terminals set) and
    /// default to `.dark` otherwise — the common case for CLI use.
    private static func guessBackground() -> Background {
        if let fgbg = Shell.env("COLORFGBG") {
            let parts = fgbg.split(separator: ";")
            if let last = parts.last, let n = Int(last) {
                // 0-6 → dark background, 7-15 → light. Standard
                // termenv heuristic.
                return n <= 6 ? .dark : .light
            }
        }
        return .dark
    }
}
