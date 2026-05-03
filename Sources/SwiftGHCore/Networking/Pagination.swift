import Foundation

/// Parses RFC 5988 `Link` headers into the URL for a given relation.
///
/// GitHub returns headers like:
/// ```
/// Link: <https://api.github.com/repos/cli/cli/issues?page=2>; rel="next",
///       <https://api.github.com/repos/cli/cli/issues?page=10>; rel="last"
/// ```
public enum LinkHeader {
    /// Returns the URL for `rel`, or `nil` if absent.
    public static func url(for rel: String, in header: String) -> URL? {
        for entry in header.split(separator: ",") {
            let parts = entry.split(separator: ";")
            guard parts.count >= 2 else { continue }
            let urlPart = parts[0].trimmingCharacters(in: .whitespaces)
            guard urlPart.hasPrefix("<"), urlPart.hasSuffix(">") else { continue }
            let urlString = String(urlPart.dropFirst().dropLast())
            for attr in parts.dropFirst() {
                let kv = attr.trimmingCharacters(in: .whitespaces)
                guard kv.hasPrefix("rel=") else { continue }
                let value = kv.dropFirst("rel=".count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if value == rel { return URL(string: urlString) }
            }
        }
        return nil
    }
}
