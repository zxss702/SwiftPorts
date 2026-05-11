import Foundation

/// Top-level style sheet. Mirrors glamour's `StyleConfig` 1:1 so a
/// `dark.json` written for upstream loads here without translation.
///
/// Missing keys default to an empty `StylePrimitive`, which the
/// cascade treats as "no opinion" — the parent style passes through.
public struct StyleConfig: Codable, Sendable, Hashable {
    public var document   : StyleBlock     = StyleBlock()
    public var blockQuote : StyleBlock     = StyleBlock()
    public var paragraph  : StyleBlock     = StyleBlock()
    public var list       : StyleList      = StyleList()

    public var heading    : StyleBlock     = StyleBlock()
    public var h1, h2, h3, h4, h5, h6 : StyleBlock

    public var text           : StylePrimitive = StylePrimitive()
    public var strikethrough  : StylePrimitive = StylePrimitive()
    public var emph           : StylePrimitive = StylePrimitive()
    public var strong         : StylePrimitive = StylePrimitive()
    public var horizontalRule : StylePrimitive = StylePrimitive()

    public var item        : StylePrimitive = StylePrimitive()
    public var enumeration : StylePrimitive = StylePrimitive()
    public var task        : StyleTask       = StyleTask()

    public var link     : StylePrimitive = StylePrimitive()
    public var linkText : StylePrimitive = StylePrimitive()

    public var image     : StylePrimitive = StylePrimitive()
    public var imageText : StylePrimitive = StylePrimitive()

    public var code      : StyleBlock      = StyleBlock()
    public var codeBlock : StyleCodeBlock  = StyleCodeBlock()

    public var table : StyleTable = StyleTable()

    public var definitionList        : StyleBlock     = StyleBlock()
    public var definitionTerm        : StylePrimitive = StylePrimitive()
    public var definitionDescription : StylePrimitive = StylePrimitive()

    public var htmlBlock : StyleBlock = StyleBlock()
    public var htmlSpan  : StyleBlock = StyleBlock()

    public init() {
        self.h1 = StyleBlock()
        self.h2 = StyleBlock()
        self.h3 = StyleBlock()
        self.h4 = StyleBlock()
        self.h5 = StyleBlock()
        self.h6 = StyleBlock()
    }

    private enum CodingKeys: String, CodingKey {
        case document, paragraph, text, strikethrough, emph, strong, item,
             enumeration, task, link, image, code, table, h1, h2, h3, h4,
             h5, h6, heading, list
        case blockQuote            = "block_quote"
        case horizontalRule        = "hr"
        case linkText              = "link_text"
        case imageText             = "image_text"
        case codeBlock             = "code_block"
        case definitionList        = "definition_list"
        case definitionTerm        = "definition_term"
        case definitionDescription = "definition_description"
        case htmlBlock             = "html_block"
        case htmlSpan              = "html_span"
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func b(_ k: CodingKeys) throws -> StyleBlock {
            try c.decodeIfPresent(StyleBlock.self, forKey: k) ?? StyleBlock()
        }
        func p(_ k: CodingKeys) throws -> StylePrimitive {
            try c.decodeIfPresent(StylePrimitive.self, forKey: k) ?? StylePrimitive()
        }
        self.document   = try b(.document)
        self.blockQuote = try b(.blockQuote)
        self.paragraph  = try b(.paragraph)
        self.list       = try c.decodeIfPresent(StyleList.self,  forKey: .list)
                          ?? StyleList()
        self.heading    = try b(.heading)
        self.h1 = try b(.h1); self.h2 = try b(.h2); self.h3 = try b(.h3)
        self.h4 = try b(.h4); self.h5 = try b(.h5); self.h6 = try b(.h6)
        self.text           = try p(.text)
        self.strikethrough  = try p(.strikethrough)
        self.emph           = try p(.emph)
        self.strong         = try p(.strong)
        self.horizontalRule = try p(.horizontalRule)
        self.item        = try p(.item)
        self.enumeration = try p(.enumeration)
        self.task        = try c.decodeIfPresent(StyleTask.self, forKey: .task)
                           ?? StyleTask()
        self.link     = try p(.link)
        self.linkText = try p(.linkText)
        self.image     = try p(.image)
        self.imageText = try p(.imageText)
        self.code      = try b(.code)
        self.codeBlock = try c.decodeIfPresent(StyleCodeBlock.self, forKey: .codeBlock)
                         ?? StyleCodeBlock()
        self.table = try c.decodeIfPresent(StyleTable.self, forKey: .table)
                     ?? StyleTable()
        self.definitionList        = try b(.definitionList)
        self.definitionTerm        = try p(.definitionTerm)
        self.definitionDescription = try p(.definitionDescription)
        self.htmlBlock = try b(.htmlBlock)
        self.htmlSpan  = try b(.htmlSpan)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(document,             forKey: .document)
        try c.encode(blockQuote,           forKey: .blockQuote)
        try c.encode(paragraph,            forKey: .paragraph)
        try c.encode(list,                 forKey: .list)
        try c.encode(heading,              forKey: .heading)
        try c.encode(h1, forKey: .h1); try c.encode(h2, forKey: .h2)
        try c.encode(h3, forKey: .h3); try c.encode(h4, forKey: .h4)
        try c.encode(h5, forKey: .h5); try c.encode(h6, forKey: .h6)
        try c.encode(text,                 forKey: .text)
        try c.encode(strikethrough,        forKey: .strikethrough)
        try c.encode(emph,                 forKey: .emph)
        try c.encode(strong,               forKey: .strong)
        try c.encode(horizontalRule,       forKey: .horizontalRule)
        try c.encode(item,                 forKey: .item)
        try c.encode(enumeration,          forKey: .enumeration)
        try c.encode(task,                 forKey: .task)
        try c.encode(link,                 forKey: .link)
        try c.encode(linkText,             forKey: .linkText)
        try c.encode(image,                forKey: .image)
        try c.encode(imageText,            forKey: .imageText)
        try c.encode(code,                 forKey: .code)
        try c.encode(codeBlock,            forKey: .codeBlock)
        try c.encode(table,                forKey: .table)
        try c.encode(definitionList,       forKey: .definitionList)
        try c.encode(definitionTerm,       forKey: .definitionTerm)
        try c.encode(definitionDescription, forKey: .definitionDescription)
        try c.encode(htmlBlock,            forKey: .htmlBlock)
        try c.encode(htmlSpan,             forKey: .htmlSpan)
    }
}
