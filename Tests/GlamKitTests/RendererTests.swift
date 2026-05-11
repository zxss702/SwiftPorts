import Foundation
import ShellKit
import Testing
@testable import GlamKit

@Suite struct RendererTests {

    /// Forces the `notty` (no-color) style so we can do exact string
    /// assertions without ANSI noise.
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

    @Test func headingsKeepHashPrefix() throws {
        let out = try render("# Hello\n\n## World\n")
        #expect(out.contains("# Hello"))
        #expect(out.contains("## World"))
    }

    @Test func paragraphsWrap() throws {
        let lorem = String(repeating: "word ", count: 30)
        let out = try render(lorem, wordWrap: 40)
        let lines = out.split(separator: "\n")
        // Notty has a document margin of 2, so allow margin chars
        // when checking width.
        for line in lines where !line.isEmpty {
            #expect(line.count <= 60, "line too long: \(line)")
        }
    }

    @Test func inlineCodeUsesPrefixSuffix() throws {
        let out = try render("Run `swift build` now.")
        #expect(out.contains("`swift build`"))
    }

    @Test func bundledStylesDecode() throws {
        for style in BundledStyle.allCases {
            _ = try StyleConfig.bundled(style)
        }
    }

    @Test func linksRenderURLWhenHyperlinksOff() throws {
        let out = try render("Read [the docs](https://example.com).")
        #expect(out.contains("https://example.com"))
        #expect(out.contains("the docs"))
    }

    @Test func unorderedListBullets() throws {
        let out = try render("- one\n- two\n- three")
        #expect(out.contains("• one"))
        #expect(out.contains("• two"))
        #expect(out.contains("• three"))
    }

    @Test func taskListCheckboxes() throws {
        let out = try render("- [x] done\n- [ ] open")
        #expect(out.contains("[x] done"))
        #expect(out.contains("[ ] open"))
    }

    /// Regression for Codex review on PR #24 — a missing or invalid
    /// `GLAMOUR_STYLE` file must not abort rendering. The renderer
    /// should fall back to the terminal-derived default just like
    /// glamour's `RenderWithEnvironmentConfig` does.
    ///
    /// Uses ShellKit's TaskLocal `Shell.current` to inject a fake
    /// `GLAMOUR_STYLE` rather than mutating the process env. That
    /// keeps the test thread-safe and avoids libc `setenv` (which
    /// isn't in scope on Windows under Swift 6.3).
    @Test func autoStyleSurvivesBadGlamourStyleEnv() throws {
        let fakeShell = Shell(
            environment: Environment(
                variables: ["GLAMOUR_STYLE": "/tmp/glam-missing-\(UUID().uuidString).json"]
            )
        )
        try Shell.$current.withValue(fakeShell) {
            let renderer = try Renderer(
                style: .auto,
                terminal: Terminal(
                    colorEnabled: false,
                    trueColor: false,
                    eightBitColor: false,
                    hyperlinks: false,
                    background: .dark
                )
            )
            let out = try renderer.render("# Hi")
            #expect(out.contains("# Hi"))
        }
    }

    /// Regression for Codex review on PR #24 — `[/issues](/issues)`
    /// with `--base-url=https://example.com/foo/bar` should resolve
    /// to `https://example.com/issues`, not `https://example.com/foo/issues`.
    @Test func rootRelativeLinkPreservesLeadingSlash() throws {
        let renderer = try Renderer(
            style: .bundled(.notty),
            baseURL: "https://example.com/foo/bar",
            terminal: Terminal(
                colorEnabled: false,
                trueColor: false,
                eightBitColor: false,
                hyperlinks: false,
                background: .none
            )
        )
        let out = try renderer.render("See [the issues](/issues).")
        #expect(out.contains("https://example.com/issues"),
                "got: \(out)")
        #expect(!out.contains("https://example.com/foo/issues"))
    }

    /// Path-relative links (no leading slash) must still resolve
    /// under the base path so `[howto](docs/howto)` works.
    @Test func pathRelativeLinkResolvesUnderBase() throws {
        let renderer = try Renderer(
            style: .bundled(.notty),
            baseURL: "https://example.com/foo/",
            terminal: Terminal(
                colorEnabled: false,
                trueColor: false,
                eightBitColor: false,
                hyperlinks: false,
                background: .none
            )
        )
        let out = try renderer.render("See [howto](docs/howto).")
        #expect(out.contains("https://example.com/foo/docs/howto"),
                "got: \(out)")
    }
}
