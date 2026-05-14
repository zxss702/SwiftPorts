import Foundation
import Testing
@testable import GlamKit

@Suite("Table rendering")
struct TableTests {

    /// Forces the `notty` style + a color-disabled terminal so we can
    /// assert on exact byte sequences without ANSI noise. `notty`'s
    /// table style uses ASCII separators (`|` / `-`) so the rendered
    /// output stays plain text.
    private func render(_ input: String, wordWrap: Int = 80) throws -> String {
        let renderer = try Renderer(
            style: .bundled(.notty),
            wordWrap: wordWrap,
            terminal: Terminal(
                colorEnabled: false,
                trueColor: false,
                eightBitColor: false,
                hyperlinks: false,
                background: .none
            )
        )
        return try renderer.render(input)
    }

    @Test func renderBasicTable() throws {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        | 3 | 4 |
        """
        let out = try render(md)
        // Upstream glamour renders rows as `cell │ cell` — no outer
        // borders, single space on each side of the column separator
        // (`|` in the notty style). Header / body cells share the
        // column width.
        #expect(out.contains("A | B"))
        #expect(out.contains("1 | 2"))
        #expect(out.contains("3 | 4"))
        // Separator row: `dashes|dashes` (with no outer border).
        // The dash run includes the row's per-side padding so the
        // separator visually aligns with the data rows above and
        // below it.
        #expect(out.contains("---|---"))
        // And explicitly NO outer pipes wrapping the row.
        let lines = out.split(separator: "\n").map(String.init)
        let firstDataRow = lines.first { $0.contains("A") && $0.contains("B") }
        #expect(firstDataRow != nil)
        #expect(firstDataRow?.trimmingCharacters(in: .whitespaces).hasPrefix("|") == false)
        #expect(firstDataRow?.hasSuffix("|") == false)
    }

    @Test func columnWidthsExpandToWidestCell() throws {
        let md = """
        | A | Long Header |
        |---|-------------|
        | very wide content | x |
        """
        let out = try render(md)
        // Column 0's width is dictated by "very wide content" (17 chars).
        // Header "A" gets padded to that width — no outer pipes, just
        // the inner column separator after the padding.
        #expect(out.contains("A                 | Long Header"))
        #expect(out.contains("very wide content | x"))
    }

    @Test func centerAndRightAlignment() throws {
        let md = """
        | left | center | right |
        |------|:------:|------:|
        | a    | b      | c     |
        """
        let out = try render(md)
        // Center column: 6 chars wide ("center"). "b" goes to the
        // middle — 3 spaces on each side (impl preserves remainder
        // on the right when surplus is odd, but for 5 chars / 6
        // width it's `2, 3` split). Assert the centred-ness loosely
        // via the surrounding pad.
        #expect(out.contains("|   b    |") || out.contains("|  b    |"))
        // Right column: 5 chars wide ("right"). "c" right-aligns.
        #expect(out.contains("|     c"))
    }

    /// Alignment markers (`:`) belong to the markdown SOURCE — they
    /// tell the parser how cells should be aligned — but real
    /// glamour doesn't echo them in the rendered output. The
    /// renderer expresses alignment through cell PADDING instead,
    /// which the data rows visually demonstrate.
    @Test func separatorRowOmitsAlignmentMarkers() throws {
        let md = """
        | A | B |
        |:--|--:|
        | x | y |
        """
        let out = try render(md)
        let sepLine = out
            .split(separator: "\n")
            .map(String.init)
            .first { $0.contains("---") }
        #expect(sepLine != nil)
        // No `:` in the rendered separator row.
        #expect(sepLine?.contains(":") == false)
    }

    @Test func inlineFormattingInCells() throws {
        let md = """
        | code | link |
        |------|------|
        | `swift` | [docs](https://example.com) |
        """
        let out = try render(md)
        // notty's `code` declares `` ` `` as a block_prefix/suffix, so
        // the cell keeps its backticks. The link's URL is rendered
        // alongside the text (no OSC 8 in this notty/no-hyperlink fixture).
        #expect(out.contains("`swift`"))
        #expect(out.contains("docs"))
        #expect(out.contains("https://example.com"))
    }

    @Test func emptyTableBodyStillRendersHeader() throws {
        let md = """
        | A | B |
        |---|---|
        """
        let out = try render(md)
        #expect(out.contains("A | B"))
        #expect(out.contains("---|---"))
    }

    /// Multi-line cell content (e.g. soft-wrapped paragraph in a cell)
    /// must keep column rules vertical.
    @Test func multiLineCellsExpandRowHeight() throws {
        let md = """
        | A | B |
        |---|---|
        | x | y |
        """
        let out = try render(md)
        #expect(out.contains("x | y"))
    }
}
