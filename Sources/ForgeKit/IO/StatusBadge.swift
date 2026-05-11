import Foundation
import ShellKit

/// Issue / PR / MR / release / workflow-run state badges, colorized
/// to match upstream `gh` / `glab` defaults. Pass `enabled: false`
/// (typically derived from a `--color={auto,always,never}` flag) to
/// get plain text — call sites stay unconditional.
public enum StatusBadge {
    /// Open issues / open PRs / open MRs — green.
    public static func open(_ text: String = "open",   enabled: Bool = true) -> String { color(text, sgr: "32", enabled: enabled) }
    /// Closed issues / closed PRs / declined MRs — magenta. Matches
    /// real `gh` and `glab`'s `closed` color.
    public static func closed(_ text: String = "closed", enabled: Bool = true) -> String { color(text, sgr: "35", enabled: enabled) }
    /// Merged PR / MR — magenta (same family as closed).
    public static func merged(_ text: String = "merged", enabled: Bool = true) -> String { color(text, sgr: "35", enabled: enabled) }
    /// Draft PR — yellow, matches `gh`.
    public static func draft(_ text: String = "draft",  enabled: Bool = true) -> String { color(text, sgr: "33", enabled: enabled) }
    /// Workflow-run success / job completed — green.
    public static func success(_ text: String = "success", enabled: Bool = true) -> String { color(text, sgr: "32", enabled: enabled) }
    /// Workflow-run / job failure — red.
    public static func failure(_ text: String = "failure", enabled: Bool = true) -> String { color(text, sgr: "31", enabled: enabled) }
    /// Workflow-run / job in progress — yellow.
    public static func inProgress(_ text: String = "in_progress", enabled: Bool = true) -> String { color(text, sgr: "33", enabled: enabled) }
    /// Generic "muted" tone used for dates, IDs, etc. — bright black (gray).
    public static func muted(_ text: String, enabled: Bool = true) -> String { color(text, sgr: "90", enabled: enabled) }

    private static func color(_ text: String, sgr: String, enabled: Bool) -> String {
        guard enabled, !text.isEmpty else { return text }
        return "\u{1B}[\(sgr)m\(text)\u{1B}[m"
    }
}

/// Color a GitHub / GitLab issue/PR label by its hex tag color when
/// the terminal supports truecolor. Falls back to plain text
/// otherwise so the caller can wrap label rendering unconditionally.
///
/// Named `LabelChip` instead of plain `Label` to avoid colliding
/// with the GitHub API model (`GitHub.Label`).
public enum LabelChip {
    public static func colored(
        name: String,
        hex: String?,
        enabled: Bool = true,
        trueColor: Bool? = nil
    ) -> String {
        let tc = trueColor ?? defaultTrueColor()
        guard enabled, tc,
              let hex,
              let (r, g, b) = parseHex(hex)
        else { return name }
        // Pick black-or-white foreground based on perceived luminance —
        // same readable-contrast rule GitHub uses on its web UI.
        let fg = luminance(r: r, g: g, b: b) > 0.5 ? "0" : "255"
        return "\u{1B}[48;2;\(r);\(g);\(b);38;5;\(fg)m \(name) \u{1B}[m"
    }

    /// Conservative: only emit truecolor escapes when color is
    /// enabled AND `COLORTERM` advertises 24-bit support.
    private static func defaultTrueColor() -> Bool {
        guard ColorChoice.auto.resolved() else { return false }
        let ct = (Shell.env("COLORTERM") ?? "").lowercased()
        return ct == "truecolor" || ct == "24bit"
    }

    private static func parseHex(_ hex: String) -> (Int, Int, Int)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return (Int(v >> 16 & 0xff), Int(v >> 8 & 0xff), Int(v & 0xff))
    }

    /// ITU-R BT.601 perceived luminance, normalised to 0…1.
    private static func luminance(r: Int, g: Int, b: Int) -> Double {
        (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255.0
    }
}
