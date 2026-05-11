import Foundation
import GlamKit

/// Tiny render helper used by `gh pr|issue|release view` to display
/// the body of a remote item as ANSI-decorated Markdown.
///
/// Picks the bundled `.auto` style (which folds in `GLAMOUR_STYLE`
/// and terminal capability detection), so non-TTY callers see the
/// `notty` style and TTY callers see `dark`/`light`. Any rendering
/// error falls back to the raw body — never the wrong thing to do
/// when displaying user-supplied text.
enum MarkdownBody {
    static func render(_ body: String) -> String {
        do {
            return try Glam.render(body)
        } catch {
            return body
        }
    }
}
