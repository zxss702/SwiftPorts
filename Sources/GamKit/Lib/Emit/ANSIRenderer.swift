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
        // Apply the document margins to the entire output.
        let doc = MarginWriter.apply(
            documentBlock.buffer,
            indent: 0,
            indentToken: " ",
            margin: Int(style.document.margin ?? 0),
            width: max(0, wordWrap - 2 * Int(style.document.margin ?? 0)),
            style: style.document.style,
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
        let merged = Cascade.block(stack.last?.style ?? StyleBlock(), style.paragraph)
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
        let inner = MarginWriter.apply(
            content,
            indent: 0,
            indentToken: " ",
            margin: 0,
            width: currentWidth,
            style: blockStyle.style,
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

    /// Apply block_prefix / prefix / suffix / block_suffix around
    /// already-styled content.
    private func prefixSuffixed(_ s: String, style: StylePrimitive) -> String {
        var out = ""
        if let bp = style.blockPrefix { out += bp }
        if let p = style.prefix       { out += p }
        out += s
        if let s2 = style.suffix      { out += s2 }
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
