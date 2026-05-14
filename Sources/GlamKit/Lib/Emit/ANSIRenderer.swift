import Foundation
import Markdown

/// Walks a swift-markdown `Document` and emits ANSI-decorated text.
/// One renderer instance corresponds to one document — internal
/// state (block stack, current indent) is throwaway.
///
/// Block elements are rendered into a private buffer, then the
/// margin/indent frame is applied at finish time. Inline elements
/// concatenate into the current buffer directly. This matches
/// glamour's two-pass design without the goldmark-callback plumbing.
final class ANSIRenderer {

    let style: StyleConfig
    let terminal: Terminal
    let wordWrap: Int
    let baseURL: String?

    /// Stack of pending block scopes. The top of the stack is the
    /// block currently accepting writes from inline emitters.
    private var stack: [BlockFrame] = []

    /// Top-level buffer — everything ultimately concatenates here.
    private var output: String = ""

    init(style: StyleConfig,
         terminal: Terminal,
         wordWrap: Int,
         baseURL: String?) {
        self.style    = style
        self.terminal = terminal
        self.wordWrap = wordWrap
        self.baseURL  = baseURL
    }

    /// Render the document and return the final string.
    func render(_ document: Document) -> String {
        // Push the document block so margins/indents accumulate from
        // its declared values (typically `margin: 2` on dark/light).
        pushBlock(style: style.document)
        visitChildren(of: document)
        let documentBlock = popBlock()
        // Apply the document margins to the entire output. Document
        // is a true block — fill the bg across the page if the style
        // calls for one.
        let doc = MarginWriter.apply(
            documentBlock.buffer,
            indent: 0,
            indentToken: " ",
            margin: Int(style.document.margin ?? 0),
            width: max(0, wordWrap - 2 * Int(style.document.margin ?? 0)),
            style: style.document.style,
            fillBackground: true,
            on: terminal
        )
        return prefixSuffixed(doc, style: style.document.style)
    }

    // MARK: - Block stack

    private struct BlockFrame {
        var buffer: String = ""
        var style: StyleBlock
    }

    private func pushBlock(style: StyleBlock) {
        stack.append(BlockFrame(style: style))
    }

    @discardableResult
    private func popBlock() -> BlockFrame {
        stack.removeLast()
    }

    private var topIndex: Int? {
        stack.isEmpty ? nil : stack.count - 1
    }

    /// Write to the current top-of-stack block buffer, or to the
    /// final output if no block is active.
    private func write(_ s: String) {
        if let i = topIndex {
            stack[i].buffer += s
        } else {
            output += s
        }
    }

    /// Current effective word-wrap width inside the active stack.
    /// Subtract the indent depth + per-block margin so block content
    /// doesn't overflow when nested.
    private var currentWidth: Int {
        let indent = stack.reduce(0) { $0 + Int($1.style.indent ?? 0) }
        let margin = stack.reduce(0) { $0 + Int($1.style.margin ?? 0) }
        return max(0, wordWrap - indent - 2 * margin)
    }

    // MARK: - Walk dispatch

    private func visit(_ markup: Markup) {
        switch markup {
        case let heading as Heading:               visitHeading(heading)
        case let paragraph as Paragraph:           visitParagraph(paragraph)
        case let text as Text:                     write(Styled.render(text.plainText, style: style.text, on: terminal))
        case let emphasis as Emphasis:             visitEmphasis(emphasis)
        case let strong as Strong:                 visitStrong(strong)
        case let strike as Strikethrough:          visitStrikethrough(strike)
        case let inlineCode as InlineCode:         visitInlineCode(inlineCode)
        case let link as Link:                     visitLink(link)
        case let image as Image:                   visitImage(image)
        case let codeBlock as CodeBlock:           visitCodeBlock(codeBlock)
        case let blockQuote as BlockQuote:         visitBlockQuote(blockQuote)
        case let unorderedList as UnorderedList:   visitList(unorderedList, ordered: false)
        case let orderedList as OrderedList:       visitList(orderedList,   ordered: true)
        case let listItem as ListItem:             visitListItem(listItem)
        case is ThematicBreak:                     visitThematicBreak()
        case is SoftBreak:                         write(" ")
        case is LineBreak:                         write("\n")
        case let html as HTMLBlock:                visitHTMLBlock(html)
        case let inlineHTML as InlineHTML:         write(Styled.render(inlineHTML.rawHTML, style: style.htmlSpan.style, on: terminal))
        case let table as Markdown.Table:          visitTable(table)
        default:
            visitChildren(of: markup)
        }
    }

    private func visitChildren(of markup: Markup) {
        for child in markup.children { visit(child) }
    }

    // MARK: - Element renderers

    private func visitHeading(_ heading: Heading) {
        let cascadingStyles: [StyleBlock] = {
            let base = style.heading
            switch heading.level {
            case 1: return [base, style.h1]
            case 2: return [base, style.h2]
            case 3: return [base, style.h3]
            case 4: return [base, style.h4]
            case 5: return [base, style.h5]
            default: return [base, style.h6]
            }
        }()
        let merged = Cascade.blocks(cascadingStyles)

        if heading.indexInParent > 0 { write("\n") }

        let block = renderInlineBlock(merged.style) { visitChildren(of: heading) }
        emitBlock(block, with: merged, defaultMargin: false)
    }

    private func visitParagraph(_ paragraph: Paragraph) {
        if paragraph.indexInParent > 0,
           !(paragraph.parent is ListItem) {
            write("\n")
        }
        // `toBlock: false` so the AST-parent (document, blockquote,
        // list-item, …) only contributes inline colour / weight to
        // paragraph text — its own `block_prefix` / `block_suffix`
        // and inline `prefix` / `suffix` are structural decorations
        // belonging to THAT element type and must not leak into the
        // child paragraph's wrapper. The previous default-true
        // cascade was inheriting the document's `block_prefix:"\n"`
        // and `block_suffix:"\n"` onto every paragraph, producing
        // three extra blank lines around each one.
        let merged = Cascade.block(
            stack.last?.style ?? StyleBlock(),
            style.paragraph,
            toBlock: false)
        let block = renderInlineBlock(merged.style) { visitChildren(of: paragraph) }
        emitBlock(block, with: merged, defaultMargin: false, trailingNewline: true)
    }

    private func visitEmphasis(_ emphasis: Emphasis) {
        emitInlineWrapped(style.emph) { visitChildren(of: emphasis) }
    }

    private func visitStrong(_ strong: Strong) {
        emitInlineWrapped(style.strong) { visitChildren(of: strong) }
    }

    private func visitStrikethrough(_ s: Strikethrough) {
        emitInlineWrapped(style.strikethrough) { visitChildren(of: s) }
    }

    private func visitInlineCode(_ code: InlineCode) {
        let parentStyle = stack.last?.style.style ?? StylePrimitive()
        let inlineStyle = Cascade.primitive(parentStyle, style.code.style, toBlock: false)
        // glamour's `CodeSpanElement` only uses Prefix/Suffix, but the
        // notty style declares its backticks under block_prefix /
        // block_suffix — meaning upstream silently drops them for
        // inline code. We accept both forms so notty's `` ` `` is
        // honored without breaking dark/light's padding spaces.
        let openBlock  = inlineStyle.blockPrefix ?? ""
        let prefix     = inlineStyle.prefix      ?? ""
        let suffix     = inlineStyle.suffix      ?? ""
        let closeBlock = inlineStyle.blockSuffix ?? ""
        let token = openBlock + prefix + code.code + suffix + closeBlock
        write(Styled.render(token, style: inlineStyle, on: terminal))
    }

    private func visitLink(_ link: Link) {
        // Render the text in the `link_text` style first.
        let inner = capture { visitChildren(of: link) }
        let textStyle = style.linkText
        let textRendered = Styled.render(inner, style: textStyle, on: terminal)

        let href = resolveURL(link.destination ?? "")
        let isHyperlink = terminal.hyperlinks && !href.isEmpty

        if isHyperlink {
            let wrapped = Hyperlink.wrap(text: textRendered, url: href)
            write(wrapped)
        } else {
            write(textRendered)
            if !href.isEmpty {
                let hrefStyle = style.link
                write(" " + Styled.render(href, style: hrefStyle, on: terminal))
            }
        }
    }

    private func visitImage(_ image: Image) {
        let alt = capture { visitChildren(of: image) }
        let imgText = Styled.applyFormat(style.imageText.format, to: alt)
        write(Styled.render(imgText, style: style.imageText, on: terminal))
        if let src = image.source, !src.isEmpty {
            write(" " + Styled.render(resolveURL(src), style: style.image, on: terminal))
        }
    }

    private func visitCodeBlock(_ codeBlock: CodeBlock) {
        if codeBlock.indexInParent > 0 { write("\n") }
        var content = codeBlock.code
        if content.hasSuffix("\n") { content.removeLast() }
        let blockStyle = style.codeBlock.block
        // Code blocks are TRUE blocks: the bg should span the full
        // block width even on short lines, matching glamour's
        // monospaced-code-fence rendering.
        let inner = MarginWriter.apply(
            content,
            indent: 0,
            indentToken: " ",
            margin: 0,
            width: currentWidth,
            style: blockStyle.style,
            fillBackground: true,
            on: terminal
        )
        emitBlock(inner, with: blockStyle, defaultMargin: true, trailingNewline: true)
    }

    private func visitBlockQuote(_ blockQuote: BlockQuote) {
        if blockQuote.indexInParent > 0 { write("\n") }
        let block = renderInlineBlock(style.blockQuote.style) {
            visitChildren(of: blockQuote)
        }
        emitBlock(block, with: style.blockQuote, defaultMargin: true)
    }

    private func visitList(_ list: Markup, ordered: Bool) {
        if list.indexInParent > 0 { write("\n") }
        var listStyle = style.list.block
        // Nested lists indent by `level_indent`; top-level list uses
        // `indent`. Matches glamour's behavior in `elements.go`
        // (KindList branch).
        if list.parent is ListItem || list.parent is UnorderedList || list.parent is OrderedList {
            listStyle.indent = style.list.levelIndent ?? listStyle.indent
        }
        let block = renderInlineBlock(listStyle.style) {
            visitChildren(of: list)
        }
        emitBlock(block, with: listStyle, defaultMargin: true, trailingNewline: true)
    }

    private func visitListItem(_ listItem: ListItem) {
        // Choose the marker: task → checkbox, ordered → "N.", unordered → bullet.
        let marker: String
        if let task = listItem.checkbox {
            marker = task == .checked
                ? (style.task.ticked ?? "[x] ")
                : (style.task.unticked ?? "[ ] ")
        } else if let parent = listItem.parent as? OrderedList {
            let start = Int(parent.startIndex)
            let index = listItem.indexInParent + start
            let primitive = style.enumeration
            let formatted = "\(index)" + (primitive.blockPrefix ?? ". ")
            marker = Styled.render(formatted, style: primitive, on: terminal)
            renderListItem(prefix: marker, listItem: listItem)
            return
        } else {
            let primitive = style.item
            let bullet = primitive.blockPrefix ?? "• "
            marker = Styled.render(bullet, style: primitive, on: terminal)
        }
        renderListItem(prefix: marker, listItem: listItem)
    }

    private func renderListItem(prefix: String, listItem: ListItem) {
        write(prefix)
        // Render children inline (the first paragraph collapses into
        // the marker's line); subsequent blocks get their own line.
        let blocks = Array(listItem.children)
        for (index, child) in blocks.enumerated() {
            if index > 0 { write("\n") }
            if let paragraph = child as? Paragraph, index == 0 {
                visitChildren(of: paragraph)
            } else {
                visit(child)
            }
        }
        if listItem.indexInParent < (listItem.parent?.childCount ?? 0) - 1 {
            write("\n")
        }
    }

    private func visitThematicBreak() {
        let primitive = style.horizontalRule
        let raw = Styled.applyFormat(primitive.format, to: "")
        let body = raw.isEmpty
            ? String(repeating: "─", count: max(0, currentWidth))
            : raw
        write(Styled.render(body, style: primitive, on: terminal))
    }

    private func visitHTMLBlock(_ html: HTMLBlock) {
        // Strip HTML to text — gh/glab bodies occasionally contain
        // `<details>` blocks; we don't try to be clever, just emit
        // the raw text minus tags so it's at least readable.
        let stripped = html.rawHTML
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        write(Styled.render(stripped, style: style.htmlBlock.style, on: terminal))
    }

    // MARK: - Tables

    /// Render a GFM table as an ASCII grid: a header row, a row of
    /// dashes, then each body row. Honors per-column alignment
    /// (left / center / right) and uses the bundled style's
    /// `center_separator` / `column_separator` / `row_separator`
    /// tokens (default `|` / `|` / `-`, matching the notty style).
    ///
    /// Each cell is rendered through `visitChildren` (so inline
    /// formatting — emphasis, code spans, links — survives), then
    /// padded to the column's measured width. Multi-line content
    /// is laid out as stacked rows of equal-width strips so the
    /// grid stays aligned regardless of how tall any single cell
    /// turns out to be.
    private func visitTable(_ table: Markdown.Table) {
        if table.indexInParent > 0 { write("\n") }
        let columnCount = max(1, table.maxColumnCount)
        let alignments: [Markdown.Table.ColumnAlignment?] = (0..<columnCount).map { i in
            i < table.columnAlignments.count ? table.columnAlignments[i] : nil
        }

        let headerCells = extractCells(from: table.head, columnCount: columnCount)
        var bodyRows: [[String]] = []
        for child in table.body.children {
            if let row = child as? Markdown.Table.Row {
                bodyRows.append(extractCells(from: row, columnCount: columnCount))
            }
        }

        // Natural widths = max printable width of any cell in the
        // column, header included. `Wrap.printWidth` skips ANSI
        // escape sequences so styled cells still measure correctly.
        var colWidths = [Int](repeating: 0, count: columnCount)
        for (i, cell) in headerCells.enumerated() where i < columnCount {
            colWidths[i] = max(colWidths[i], maxLineWidth(cell))
        }
        for row in bodyRows {
            for (i, cell) in row.enumerated() where i < columnCount {
                colWidths[i] = max(colWidths[i], maxLineWidth(cell))
            }
        }

        // Constrain to the document width — matches upstream glamour,
        // which shrinks long columns and truncates oversized cells
        // with `…` so the table never overflows the terminal. Without
        // this, a `What it does` column carrying multi-sentence prose
        // can blow the table out past the right margin and force the
        // host terminal to soft-wrap each row.
        //
        // Layout: `cell │ cell │ cell` — N-1 separators, each
        // ` <colSep> ` = 3 printable chars.
        //
        // Allocation: columns whose natural width fits a fair share
        // of the remaining budget keep their natural width; the
        // saved space is redistributed equally across the oversized
        // columns. That gives short identifier-like columns (e.g.
        // `Product`) their natural width and lets the prose-heavy
        // column take the rest, instead of squeezing every column
        // proportionally (which mauls short columns to make room
        // for a single long one).
        let separatorBudget = max(0, columnCount - 1) * 3
        let contentBudget = max(0, currentWidth - separatorBudget)
        let naturalSum = colWidths.reduce(0, +)
        if naturalSum > contentBudget, contentBudget > 0 {
            let minWidth = 3
            var remainingBudget = contentBudget
            var remainingCols = columnCount
            // Sorted column indices, smallest natural first.
            let sortedIdx = (0..<columnCount)
                .sorted { colWidths[$0] < colWidths[$1] }
            var allocation = [Int](repeating: 0, count: columnCount)
            var oversized: [Int] = []
            for idx in sortedIdx {
                let fair = remainingCols > 0
                    ? remainingBudget / remainingCols
                    : 0
                if colWidths[idx] <= fair {
                    allocation[idx] = colWidths[idx]
                    remainingBudget -= colWidths[idx]
                    remainingCols -= 1
                } else {
                    oversized.append(idx)
                }
            }
            // Split the remaining budget equally across oversized
            // columns, with the per-column minimum.
            if !oversized.isEmpty {
                let perCol = max(minWidth, remainingBudget / oversized.count)
                var leftover = remainingBudget - perCol * oversized.count
                for idx in oversized {
                    allocation[idx] = perCol + (leftover > 0 ? 1 : 0)
                    if leftover > 0 { leftover -= 1 }
                }
            }
            // Final guard: if rounding produced a sum > budget,
            // trim from the widest column.
            while allocation.reduce(0, +) > contentBudget {
                let widestIdx = allocation.indices
                    .max(by: { allocation[$0] < allocation[$1] }) ?? 0
                if allocation[widestIdx] <= minWidth { break }
                allocation[widestIdx] -= 1
            }
            colWidths = allocation
        }

        let colSep = style.table.columnSeparator ?? "|"
        let centerSep = style.table.centerSeparator ?? colSep
        let rowSep = style.table.rowSeparator ?? "-"

        // Header.
        write(renderTableRow(headerCells, widths: colWidths,
                             alignments: alignments, columnSeparator: colSep))
        write("\n")
        // Separator row: dashes per column, the configured `center_separator`
        // (typically `|`) between columns, like real `| --- | --- |`.
        write(renderTableSeparator(widths: colWidths,
                                   alignments: alignments,
                                   rowSeparator: rowSep,
                                   centerSeparator: centerSep))
        write("\n")
        for row in bodyRows {
            write(renderTableRow(row, widths: colWidths,
                                 alignments: alignments, columnSeparator: colSep))
            write("\n")
        }
    }

    /// Pull plain inline-rendered cells out of a row-shaped markup
    /// node (either `Table.Head` or `Table.Row`). Cells with
    /// `colspan > 1` get padded with empty siblings so column
    /// indices stay aligned.
    private func extractCells<R: Markup>(
        from row: R,
        columnCount: Int
    ) -> [String] {
        var cells: [String] = []
        for child in row.children {
            guard let cell = child as? Markdown.Table.Cell else { continue }
            let text = capture { visitChildren(of: cell) }
            cells.append(text)
            let span = Int(cell.colspan)
            if span > 1 {
                for _ in 1..<span { cells.append("") }
            }
        }
        while cells.count < columnCount { cells.append("") }
        return cells
    }

    private func maxLineWidth(_ s: String) -> Int {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Wrap.printWidth(String($0)) }
            .max() ?? 0
    }

    /// Format a single row's cells into one grid line. Multi-line
    /// cells (containing `\n` characters) get expanded — each line
    /// of the tallest cell becomes its own output line, with shorter
    /// cells padded with blank strips so the column rules stay
    /// vertical.
    private func renderTableRow(
        _ cells: [String],
        widths: [Int],
        alignments: [Markdown.Table.ColumnAlignment?],
        columnSeparator: String
    ) -> String {
        // Real glamour renders rows as `cell │ cell │ cell` — no
        // outer borders, single space on each side of the column
        // separator. Cells longer than their allocated column width
        // get truncated with `…` so a wide cell doesn't shove the
        // table past the terminal margin.
        let cellLines = cells.map {
            $0.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        let height = cellLines.map(\.count).max() ?? 1
        var out: [String] = []
        for line in 0..<height {
            var cols: [String] = []
            for col in 0..<widths.count {
                let raw: String = cellLines.indices.contains(col)
                    && cellLines[col].indices.contains(line)
                    ? cellLines[col][line] : ""
                let clipped = Self.truncateToWidth(raw, widths[col])
                cols.append(padCell(clipped, width: widths[col],
                                    alignment: alignments[col] ?? .left))
            }
            out.append(cols.joined(separator: " \(columnSeparator) "))
        }
        return out.joined(separator: "\n")
    }

    /// Truncate `s` to fit in `width` printable columns, replacing
    /// the last visible character with `…` (U+2026) when the string
    /// is longer. ANSI CSI / OSC escape sequences are passed
    /// through verbatim so the styling around an inline code span
    /// or link survives the cut, and a final `\e[0m` reset is
    /// appended so any opened SGR state can't leak past the cell
    /// boundary.
    static func truncateToWidth(_ s: String, _ width: Int) -> String {
        if width <= 0 { return "" }
        if Wrap.printWidth(s) <= width { return s }
        if width == 1 { return "…" }

        let chars = Array(s)
        let printableBudget = width - 1   // reserve 1 for `…`
        var out = ""
        var printed = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\u{1B}", i + 1 < chars.count, chars[i + 1] == "[" {
                // CSI sequence: copy through the final letter.
                let start = i
                i += 2
                while i < chars.count, !chars[i].isLetter { i += 1 }
                if i < chars.count { i += 1 }
                out.append(String(chars[start..<i]))
                continue
            }
            if c == "\u{1B}", i + 1 < chars.count, chars[i + 1] == "]" {
                // OSC sequence: copy through BEL or ESC\.
                let start = i
                i += 2
                while i < chars.count {
                    if chars[i] == "\u{07}" { i += 1; break }
                    if chars[i] == "\u{1B}",
                       i + 1 < chars.count, chars[i + 1] == "\\" {
                        i += 2
                        break
                    }
                    i += 1
                }
                out.append(String(chars[start..<i]))
                continue
            }
            if printed >= printableBudget { break }
            out.append(c)
            printed += 1
            i += 1
        }
        return out + "\u{1B}[0m…"
    }

    private func renderTableSeparator(
        widths: [Int],
        alignments: [Markdown.Table.ColumnAlignment?],
        rowSeparator: String,
        centerSeparator: String
    ) -> String {
        // Matching the row renderer: no outer borders, just
        // `dashes┼dashes┼dashes`. The dash run includes the two
        // padding columns the row renderer adds around each cell
        // (`<sep>` becomes ` <sep> `), so vertical alignment between
        // the separator row and the data rows is preserved. We do
        // NOT emit the GFM `:`-alignment markers in the visual
        // output — those belong in the markdown SOURCE, not in the
        // rendered table.
        let _ = alignments
        var parts: [String] = []
        for col in 0..<widths.count {
            let dashCount = max(1, widths[col] + 2)
            parts.append(String(repeating: rowSeparator, count: dashCount))
        }
        return parts.joined(separator: centerSeparator)
    }

    private func padCell(
        _ text: String,
        width: Int,
        alignment: Markdown.Table.ColumnAlignment
    ) -> String {
        let printed = Wrap.printWidth(text)
        guard printed < width else { return text }
        let pad = width - printed
        switch alignment {
        case .right:  return String(repeating: " ", count: pad) + text
        case .center:
            let left = pad / 2
            let right = pad - left
            return String(repeating: " ", count: left) + text + String(repeating: " ", count: right)
        case .left:   return text + String(repeating: " ", count: pad)
        }
    }

    // MARK: - Block helpers

    /// Capture inline emissions into a string buffer, restoring the
    /// current top frame afterward.
    private func capture(_ body: () -> Void) -> String {
        pushBlock(style: StyleBlock())
        body()
        return popBlock().buffer
    }

    /// Run `body`, capture its emissions, and apply word-wrap.
    private func renderInlineBlock(
        _ style: StylePrimitive,
        body: () -> Void
    ) -> String {
        let raw = capture(body)
        return Wrap.wrap(raw, width: currentWidth)
    }

    /// Emit a fully-rendered block: apply margin/indent/style, then
    /// write to the parent block buffer (or top-level output).
    ///
    /// `defaultMargin` doubles as "true-block" indicator — code
    /// blocks / block quotes / lists / tables fill their bg across
    /// the block width; inline-styled elements (headings,
    /// paragraphs) leave the bg covering just the styled text and
    /// its inline prefix/suffix, matching upstream glamour.
    private func emitBlock(
        _ content: String,
        with block: StyleBlock,
        defaultMargin: Bool,
        trailingNewline: Bool = false
    ) {
        let margin = Int(block.margin ?? (defaultMargin ? 0 : 0))
        let indent = Int(block.indent ?? 0)
        let token = block.indentToken ?? " "
        let framed = MarginWriter.apply(
            content,
            indent: indent,
            indentToken: token,
            margin: margin,
            width: currentWidth,
            style: block.style,
            fillBackground: defaultMargin,
            on: terminal
        )
        let body = prefixSuffixed(framed, style: block.style)
        write(body)
        if trailingNewline { write("\n") }
    }

    /// Run `body`, then wrap its captured output in the SGR envelope
    /// for `style` and write to the current block.
    private func emitInlineWrapped(_ style: StylePrimitive,
                                   _ body: () -> Void) {
        let inner = capture(body)
        write(Styled.render(inner, style: style, on: terminal))
    }

    /// Apply `block_prefix` / `block_suffix` around already-styled
    /// content. The inline `prefix` / `suffix` are now applied
    /// INSIDE the SGR envelope by `MarginWriter.apply` so the
    /// styled bg/fg covers them — matching upstream glamour. Only
    /// the block-level markers (e.g. blockquote's `> `) remain
    /// outside.
    private func prefixSuffixed(_ s: String, style: StylePrimitive) -> String {
        var out = ""
        if let bp = style.blockPrefix { out += bp }
        out += s
        if let bs = style.blockSuffix { out += bs }
        return out
    }

    private func resolveURL(_ raw: String) -> String {
        guard let baseURL, !baseURL.isEmpty, !raw.isEmpty else { return raw }
        if raw.contains("://") || raw.hasPrefix("mailto:") { return raw }
        // Keep `raw` verbatim — `URL(string:relativeTo:)` follows
        // RFC 3986, so root-relative refs like `/issues` resolve
        // against the host root (`https://example.com/issues`) and
        // path-relative refs like `docs/howto` resolve under the
        // base's last directory. Glamour strips the leading slash
        // and effectively breaks host-root semantics — we match the
        // RFC instead.
        if let base = URL(string: baseURL),
           let resolved = URL(string: raw, relativeTo: base) {
            return resolved.absoluteString
        }
        return raw
    }
}
