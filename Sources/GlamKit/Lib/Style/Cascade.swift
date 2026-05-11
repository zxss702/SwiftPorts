import Foundation

/// Style inheritance — when a child style omits a field, it inherits
/// the parent's. When the child sets it, the child wins. Mirrors
/// glamour's `cascadeStylePrimitive` / `cascadeStyle` from
/// `ansi/style.go`.
public enum Cascade {
    /// Inherit primitive fields parent → child. `toBlock = true`
    /// also pulls block_prefix / prefix / suffix from the parent;
    /// `false` is for inline-into-block transitions where the
    /// surrounding fixed text shouldn't leak.
    public static func primitive(
        _ parent: StylePrimitive,
        _ child: StylePrimitive,
        toBlock: Bool = true
    ) -> StylePrimitive {
        var s = child
        // Pull every inheritable field from parent first, then let
        // the child override.
        s.color           = child.color           ?? parent.color
        s.backgroundColor = child.backgroundColor ?? parent.backgroundColor
        s.underline       = child.underline       ?? parent.underline
        s.bold            = child.bold            ?? parent.bold
        s.italic          = child.italic          ?? parent.italic
        s.crossedOut      = child.crossedOut      ?? parent.crossedOut
        s.faint           = child.faint           ?? parent.faint
        s.conceal         = child.conceal         ?? parent.conceal
        s.inverse         = child.inverse         ?? parent.inverse
        s.blink           = child.blink           ?? parent.blink
        s.upper           = child.upper           ?? parent.upper
        s.lower           = child.lower           ?? parent.lower
        s.title           = child.title           ?? parent.title
        if toBlock {
            s.blockPrefix = child.blockPrefix.flatMap { $0.isEmpty ? nil : $0 } ?? parent.blockPrefix
            s.blockSuffix = child.blockSuffix.flatMap { $0.isEmpty ? nil : $0 } ?? parent.blockSuffix
            s.prefix      = child.prefix.flatMap      { $0.isEmpty ? nil : $0 } ?? parent.prefix
            s.suffix      = child.suffix.flatMap      { $0.isEmpty ? nil : $0 } ?? parent.suffix
        }
        s.format = (child.format?.isEmpty == false) ? child.format : parent.format
        return s
    }

    /// Block-level cascade. `toBlock = true` also inherits margin /
    /// indent from the parent — used when entering a sub-block.
    public static func block(
        _ parent: StyleBlock,
        _ child: StyleBlock,
        toBlock: Bool = true
    ) -> StyleBlock {
        var s = child
        s.style = primitive(parent.style, child.style, toBlock: toBlock)
        if toBlock {
            s.margin = child.margin ?? parent.margin
            // indent doesn't cascade in glamour — each block declares
            // its own. We follow upstream here.
        }
        return s
    }

    /// Fold a list of styles left-to-right. Used when a node has
    /// multiple cascading parents (e.g. `H1` cascades through
    /// `Heading` → `H1`).
    public static func blocks(_ styles: [StyleBlock]) -> StyleBlock {
        styles.reduce(StyleBlock()) { acc, next in block(acc, next) }
    }

    /// Fold a list of primitive styles left-to-right.
    public static func primitives(_ styles: [StylePrimitive]) -> StylePrimitive {
        styles.reduce(StylePrimitive()) { acc, next in primitive(acc, next) }
    }
}
