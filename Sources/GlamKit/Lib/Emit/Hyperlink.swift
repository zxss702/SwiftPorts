import Foundation

/// OSC 8 hyperlink helpers. The escape sequence is
/// `ESC ]8;{params};{url}ESC \` to open and `ESC ]8;;ESC \` to close.
public enum Hyperlink {

    /// Wrap `text` so clicking it (on a supporting terminal) opens
    /// `url`. Caller must check `Terminal.hyperlinks` first — we don't
    /// gate here so an unsupported terminal sees the raw control
    /// sequence garbage rather than silently swallowed text.
    public static func wrap(text: String, url: String) -> String {
        let id = idHash(url)
        let open  = "\u{1B}]8;id=\(id);\(url)\u{1B}\\"
        let close = "\u{1B}]8;;\u{1B}\\"
        return open + text + close
    }

    /// FNV-1a 32-bit hash — same algorithm glamour uses
    /// (`hash/fnv.New32a`). The hash becomes the `id=` parameter so
    /// the terminal can group repeated occurrences of the same URL.
    private static func idHash(_ s: String) -> UInt32 {
        var hash: UInt32 = 0x811C9DC5
        for byte in s.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return hash
    }
}
