import Foundation
import ShellKit

/// OSC 8 hyperlink helper. Wraps `text` so that, in supporting
/// terminals (xterm, alacritty, wezterm, kitty, ghostty, iTerm2,
/// Terminal.app, GNOME Terminal, …), clicking the text opens `url`.
///
///     OSC8.wrap("#42", url: "https://github.com/owner/repo/issues/42")
///
/// In a non-supporting terminal (or when colors/links are disabled),
/// pass `enabled: false` and the helper returns `text` unchanged so
/// the call site stays unconditional.
public enum OSC8 {
    /// `enabled: nil` resolves the capability at call time using
    /// `ColorChoice.auto` rules (NO_COLOR / CLICOLOR_FORCE / TTY).
    /// Pass an explicit Bool when a `--color` flag is in play.
    public static func wrap(_ text: String, url: String, enabled: Bool? = nil) -> String {
        let on = enabled ?? defaultEnabled()
        guard on, !url.isEmpty else { return text }
        let id = idHash(url)
        let open  = "\u{1B}]8;id=\(id);\(url)\u{1B}\\"
        let close = "\u{1B}]8;;\u{1B}\\"
        return open + text + close
    }

    /// Heuristic match to glamour's `Terminal.hyperlinks` check —
    /// the same terminals that emit colored output are the ones that
    /// honor OSC 8.
    private static func defaultEnabled() -> Bool {
        guard ColorChoice.auto.resolved() else { return false }
        let term = Shell.env("TERM") ?? ""
        return term.hasPrefix("xterm")
            || term.hasPrefix("screen")
            || term.hasPrefix("tmux")
            || term.hasPrefix("alacritty")
            || term.hasPrefix("wezterm")
            || term.hasPrefix("kitty")
            || term.hasPrefix("ghostty")
    }

    /// FNV-1a 32-bit hash — same algorithm glamour uses (`hash/fnv.
    /// New32a`). The hash becomes the `id=` parameter so the terminal
    /// can group repeated occurrences of the same URL.
    private static func idHash(_ s: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return hash
    }
}
