import Foundation

/// Resolves a glamour-shaped color spec (`"234"`, `"#C4C4C4"`,
/// `"red"`) to a concrete SGR byte sequence matched to the active
/// terminal capability.
public enum Color {

    /// SGR digits for the foreground form of `spec`. Returns `nil`
    /// when the color can't be parsed or the terminal can't emit it
    /// at all (e.g. truecolor request on a 16-color terminal — we
    /// downsample to nothing rather than emit gibberish).
    public static func fg(_ spec: String, on terminal: Terminal) -> String? {
        guard terminal.colorEnabled, let resolved = parse(spec) else { return nil }
        return sgr(resolved, on: terminal, foreground: true)
    }

    public static func bg(_ spec: String, on terminal: Terminal) -> String? {
        guard terminal.colorEnabled, let resolved = parse(spec) else { return nil }
        return sgr(resolved, on: terminal, foreground: false)
    }

    /// Convenience: build the full `ESC[…m` envelope for a set of
    /// SGR fragments. Returns the empty string when no fragment
    /// would actually render — saves an empty `\u{1B}[m` that breaks
    /// some emitters.
    public static func envelope(_ fragments: [String?]) -> String {
        let kept = fragments.compactMap { $0 }.filter { !$0.isEmpty }
        guard !kept.isEmpty else { return "" }
        return "\u{1B}[" + kept.joined(separator: ";") + "m"
    }

    /// Reset SGR to defaults. Always safe to emit.
    public static let reset = "\u{1B}[0m"

    // MARK: - Parsing

    /// Internal normalized form. Glamour accepts three shapes:
    ///   - decimal 256-color index ("0".."255")
    ///   - 24-bit hex ("#RRGGBB")
    ///   - ANSI name ("red", "bright_red", …)
    enum Resolved {
        case ansi16(Int)         // 30-37 (or 40-47 for bg) / 90-97
        case ansi256(Int)        // 0-255
        case truecolor(UInt8, UInt8, UInt8)
    }

    static func parse(_ spec: String) -> Resolved? {
        let trimmed = spec.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return parseHex(trimmed) }
        if let n = Int(trimmed), (0...255).contains(n) {
            return n < 16 ? .ansi16(n) : .ansi256(n)
        }
        return parseName(trimmed.lowercased())
    }

    private static func parseHex(_ s: String) -> Resolved? {
        var hex = s
        hex.removeFirst()
        guard hex.count == 6,
              let value = UInt32(hex, radix: 16) else { return nil }
        let r = UInt8((value >> 16) & 0xff)
        let g = UInt8((value >>  8) & 0xff)
        let b = UInt8( value        & 0xff)
        return .truecolor(r, g, b)
    }

    private static func parseName(_ s: String) -> Resolved? {
        switch s {
        case "black":   return .ansi16(0)
        case "red":     return .ansi16(1)
        case "green":   return .ansi16(2)
        case "yellow":  return .ansi16(3)
        case "blue":    return .ansi16(4)
        case "magenta": return .ansi16(5)
        case "cyan":    return .ansi16(6)
        case "white":   return .ansi16(7)
        case "bright_black", "gray", "grey": return .ansi16(8)
        case "bright_red":     return .ansi16(9)
        case "bright_green":   return .ansi16(10)
        case "bright_yellow":  return .ansi16(11)
        case "bright_blue":    return .ansi16(12)
        case "bright_magenta": return .ansi16(13)
        case "bright_cyan":    return .ansi16(14)
        case "bright_white":   return .ansi16(15)
        default: return nil
        }
    }

    // MARK: - Emit

    /// Builds the SGR fragment (without the surrounding `ESC[ … m`)
    /// for a resolved color, downsampling when needed.
    static func sgr(_ resolved: Resolved, on terminal: Terminal, foreground: Bool) -> String? {
        switch resolved {
        case .truecolor(let r, let g, let b):
            if terminal.trueColor {
                return "\(foreground ? 38 : 48);2;\(r);\(g);\(b)"
            }
            if terminal.eightBitColor {
                return "\(foreground ? 38 : 48);5;\(approximate256(r, g, b))"
            }
            return ansi16Code(approximate16(r, g, b), foreground: foreground)
        case .ansi256(let n):
            if terminal.eightBitColor {
                return "\(foreground ? 38 : 48);5;\(n)"
            }
            // Downsample 256 → 16 by mapping the 6×6×6 cube + grays.
            return ansi16Code(downsample256To16(n), foreground: foreground)
        case .ansi16(let n):
            return ansi16Code(n, foreground: foreground)
        }
    }

    private static func ansi16Code(_ n: Int, foreground: Bool) -> String? {
        guard (0...15).contains(n) else { return nil }
        let base = foreground ? 30 : 40
        if n < 8 { return String(base + n) }
        return String(base + 60 + (n - 8))
    }

    // 6×6×6 cube approximation — same math everyone uses.
    private static func approximate256(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
        func bucket(_ v: UInt8) -> Int { Int(v) * 5 / 255 }
        return 16 + 36 * bucket(r) + 6 * bucket(g) + bucket(b)
    }

    // Pick the nearest of the 16 named colors. Crude but good enough
    // for the fallback path; the bundled styles target 256-color.
    private static func approximate16(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Int {
        let intensity = (Int(r) + Int(g) + Int(b)) / 3
        let bright = intensity > 127 ? 8 : 0
        let red    = r > 127 ? 1 : 0
        let green  = g > 127 ? 2 : 0
        let blue   = b > 127 ? 4 : 0
        return bright + red + green + blue
    }

    private static func downsample256To16(_ n: Int) -> Int {
        if n < 16 { return n }
        if n >= 232 {
            let level = n - 232
            return level < 12 ? 8 : 15
        }
        // 16 + 36*r + 6*g + b in 6-cube
        let idx = n - 16
        let r = idx / 36
        let g = (idx / 6) % 6
        let b = idx % 6
        return approximate16(
            UInt8(r * 51), UInt8(g * 51), UInt8(b * 51)
        )
    }
}
