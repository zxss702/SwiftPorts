import Foundation

/// The atomic styling unit. Mirrors glamour's `StylePrimitive` 1:1 —
/// every field decodes from the same JSON key, so a JSON file written
/// for upstream glamour loads here without translation.
///
/// All fields are optional. `nil` means "inherit from parent block in
/// the cascade." A `false` (e.g. `Bold = false`) is meaningful — it
/// suppresses a parent's `true`.
public struct StylePrimitive: Codable, Sendable, Hashable {
    /// Inserted before the block's content, *outside* any surrounding
    /// style. Used by headings to inject a leading blank line, etc.
    public var blockPrefix: String?
    public var blockSuffix: String?

    /// Inserted at the very start of the styled content (inside the
    /// style envelope). H1's `" "` ↔ `" "` makes the colored bar.
    public var prefix: String?
    public var suffix: String?

    /// 256-color index ("234"), ANSI named color, or 24-bit hex
    /// ("#C4C4C4"). Resolved against the active terminal capability
    /// when the style is applied.
    public var color: String?
    public var backgroundColor: String?

    public var underline: Bool?
    public var bold: Bool?
    public var italic: Bool?
    public var crossedOut: Bool?
    public var faint: Bool?
    public var conceal: Bool?
    public var inverse: Bool?
    public var blink: Bool?
    public var upper: Bool?
    public var lower: Bool?
    public var title: Bool?

    /// Optional `text/template`-style format string. Only `{{.text}}`
    /// is honored — glamour's full template engine isn't needed for
    /// the bundled styles (`Image: {{.text}} →` is the only use site).
    public var format: String?

    public init(
        blockPrefix: String? = nil,
        blockSuffix: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        color: String? = nil,
        backgroundColor: String? = nil,
        underline: Bool? = nil,
        bold: Bool? = nil,
        italic: Bool? = nil,
        crossedOut: Bool? = nil,
        faint: Bool? = nil,
        conceal: Bool? = nil,
        inverse: Bool? = nil,
        blink: Bool? = nil,
        upper: Bool? = nil,
        lower: Bool? = nil,
        title: Bool? = nil,
        format: String? = nil
    ) {
        self.blockPrefix = blockPrefix
        self.blockSuffix = blockSuffix
        self.prefix = prefix
        self.suffix = suffix
        self.color = color
        self.backgroundColor = backgroundColor
        self.underline = underline
        self.bold = bold
        self.italic = italic
        self.crossedOut = crossedOut
        self.faint = faint
        self.conceal = conceal
        self.inverse = inverse
        self.blink = blink
        self.upper = upper
        self.lower = lower
        self.title = title
        self.format = format
    }

    private enum CodingKeys: String, CodingKey {
        case blockPrefix     = "block_prefix"
        case blockSuffix     = "block_suffix"
        case prefix
        case suffix
        case color
        case backgroundColor = "background_color"
        case underline, bold, italic
        case crossedOut      = "crossed_out"
        case faint, conceal, inverse, blink
        case upper, lower, title, format
    }
}

/// Block-level style additions: indent / margin / indent-token.
public struct StyleBlock: Codable, Sendable, Hashable {
    public var style: StylePrimitive
    public var indent: UInt?
    public var indentToken: String?
    public var margin: UInt?

    public init(style: StylePrimitive = StylePrimitive(),
                indent: UInt? = nil,
                indentToken: String? = nil,
                margin: UInt? = nil) {
        self.style = style
        self.indent = indent
        self.indentToken = indentToken
        self.margin = margin
    }

    /// The block-level fields decode at the same level as the
    /// primitive fields (glamour's JSON is flat), so we hand-roll
    /// the en/decode rather than letting the synthesised one nest.
    private enum CodingKeys: String, CodingKey {
        case indent, margin
        case indentToken = "indent_token"
    }

    public init(from decoder: Decoder) throws {
        self.style = try StylePrimitive(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.indent = try c.decodeIfPresent(UInt.self, forKey: .indent)
        self.indentToken = try c.decodeIfPresent(String.self, forKey: .indentToken)
        self.margin = try c.decodeIfPresent(UInt.self, forKey: .margin)
    }

    public func encode(to encoder: Encoder) throws {
        try style.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(indent, forKey: .indent)
        try c.encodeIfPresent(indentToken, forKey: .indentToken)
        try c.encodeIfPresent(margin, forKey: .margin)
    }
}

/// Task-list checkbox style.
public struct StyleTask: Codable, Sendable, Hashable {
    public var style: StylePrimitive
    public var ticked: String?
    public var unticked: String?

    public init(style: StylePrimitive = StylePrimitive(),
                ticked: String? = nil,
                unticked: String? = nil) {
        self.style = style
        self.ticked = ticked
        self.unticked = unticked
    }

    private enum CodingKeys: String, CodingKey { case ticked, unticked }

    public init(from decoder: Decoder) throws {
        self.style = try StylePrimitive(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ticked = try c.decodeIfPresent(String.self, forKey: .ticked)
        self.unticked = try c.decodeIfPresent(String.self, forKey: .unticked)
    }

    public func encode(to encoder: Encoder) throws {
        try style.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(ticked, forKey: .ticked)
        try c.encodeIfPresent(unticked, forKey: .unticked)
    }
}

/// List-block style with `level_indent`.
public struct StyleList: Codable, Sendable, Hashable {
    public var block: StyleBlock
    public var levelIndent: UInt?

    public init(block: StyleBlock = StyleBlock(), levelIndent: UInt? = nil) {
        self.block = block
        self.levelIndent = levelIndent
    }

    private enum CodingKeys: String, CodingKey { case levelIndent = "level_indent" }

    public init(from decoder: Decoder) throws {
        self.block = try StyleBlock(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.levelIndent = try c.decodeIfPresent(UInt.self, forKey: .levelIndent)
    }

    public func encode(to encoder: Encoder) throws {
        try block.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(levelIndent, forKey: .levelIndent)
    }
}

/// Table style with single-character separators.
public struct StyleTable: Codable, Sendable, Hashable {
    public var block: StyleBlock
    public var centerSeparator: String?
    public var columnSeparator: String?
    public var rowSeparator: String?

    public init(block: StyleBlock = StyleBlock(),
                centerSeparator: String? = nil,
                columnSeparator: String? = nil,
                rowSeparator: String? = nil) {
        self.block = block
        self.centerSeparator = centerSeparator
        self.columnSeparator = columnSeparator
        self.rowSeparator = rowSeparator
    }

    private enum CodingKeys: String, CodingKey {
        case centerSeparator = "center_separator"
        case columnSeparator = "column_separator"
        case rowSeparator    = "row_separator"
    }

    public init(from decoder: Decoder) throws {
        self.block = try StyleBlock(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.centerSeparator = try c.decodeIfPresent(String.self, forKey: .centerSeparator)
        self.columnSeparator = try c.decodeIfPresent(String.self, forKey: .columnSeparator)
        self.rowSeparator    = try c.decodeIfPresent(String.self, forKey: .rowSeparator)
    }

    public func encode(to encoder: Encoder) throws {
        try block.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(centerSeparator, forKey: .centerSeparator)
        try c.encodeIfPresent(columnSeparator, forKey: .columnSeparator)
        try c.encodeIfPresent(rowSeparator,    forKey: .rowSeparator)
    }
}

/// Code-block style. Chroma palette is decoded but ignored in this
/// release — fenced code renders with the block's color + margin and
/// no per-token highlighting (glamour's biggest dep was the Chroma
/// lexer; deferring it keeps the port pure-Swift).
public struct StyleCodeBlock: Codable, Sendable, Hashable {
    public var block: StyleBlock
    public var theme: String?

    public init(block: StyleBlock = StyleBlock(), theme: String? = nil) {
        self.block = block
        self.theme = theme
    }

    private enum CodingKeys: String, CodingKey { case theme, chroma }

    public init(from decoder: Decoder) throws {
        self.block = try StyleBlock(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try c.decodeIfPresent(String.self, forKey: .theme)
        // `chroma` is intentionally swallowed — see type doc.
    }

    public func encode(to encoder: Encoder) throws {
        try block.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(theme, forKey: .theme)
    }
}
