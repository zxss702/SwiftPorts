import Foundation
import Markdown
import ShellKit

/// Glamour-compatible markdown → ANSI renderer.
///
/// Typical use:
///
///     // Auto-pick the bundled style based on terminal capability.
///     print(try Glam.render(body))
///
///     // Force one of the bundled styles.
///     print(try Glam.render(body, style: .bundled(.dark)))
///
///     // Render in a non-TTY pipeline.
///     print(try Glam.render(body, style: .bundled(.notty)))
///
public enum Glam {

    /// Style selector. `.auto` resolves at render time from the
    /// active terminal capability and `GLAMOUR_STYLE` env. The
    /// remaining cases force a specific style.
    public enum Style: Sendable {
        case auto
        case bundled(BundledStyle)
        case custom(StyleConfig)
    }

    /// One-shot convenience. Constructs a renderer and runs it.
    public static func render(
        _ markdown: String,
        style: Style = .auto,
        wordWrap: Int? = nil,
        baseURL: String? = nil,
        terminal override: Terminal? = nil
    ) throws -> String {
        let renderer = try Renderer(
            style:    style,
            wordWrap: wordWrap,
            baseURL:  baseURL,
            terminal: override
        )
        return try renderer.render(markdown)
    }
}

/// Reusable renderer. Configure once, render many.
public struct Renderer: Sendable {

    /// Resolved style config (after `.auto` selection).
    public let style: StyleConfig

    /// Terminal profile in effect.
    public let terminal: Terminal

    /// Configured word-wrap width.
    public let wordWrap: Int

    public let baseURL: String?

    public init(
        style: Glam.Style = .auto,
        wordWrap: Int? = nil,
        baseURL: String? = nil,
        terminal override: Terminal? = nil
    ) throws {
        let term = override ?? Terminal.detected
        self.terminal = term
        self.style    = try Renderer.resolveStyle(style, terminal: term)
        // 80 matches glamour's default. Caller-supplied wins. We
        // honor `GH_MDWIDTH` like gh's wrapper to make adopters
        // happy.
        if let width = wordWrap {
            self.wordWrap = max(0, width)
        } else if let env = Shell.env("GH_MDWIDTH"), let n = Int(env), n >= 0 {
            self.wordWrap = n
        } else {
            self.wordWrap = 80
        }
        self.baseURL = baseURL
    }

    /// Render `markdown` to an ANSI-decorated string.
    public func render(_ markdown: String) throws -> String {
        let document = Document(parsing: markdown, options: [])
        let renderer = ANSIRenderer(
            style:    style,
            terminal: terminal,
            wordWrap: wordWrap,
            baseURL:  baseURL
        )
        return renderer.render(document)
    }

    // MARK: - Resolution

    private static func resolveStyle(
        _ requested: Glam.Style,
        terminal: Terminal
    ) throws -> StyleConfig {
        switch requested {
        case .custom(let config): return config
        case .bundled(let style): return try StyleConfig.bundled(style)
        case .auto:
            // 1. `GLAMOUR_STYLE` env wins — but a missing file or
            //    bad JSON must NOT abort rendering. `GLAMOUR_STYLE=
            //    /tmp/missing.json gh pr view 42` should still print
            //    the body, just falling back to the terminal-derived
            //    default. Mirrors glamour's permissive behavior — its
            //    `RenderWithEnvironmentConfig` falls back to dark
            //    when the env's value is unrecognised.
            if let env = Shell.env("GLAMOUR_STYLE"), !env.isEmpty,
               let loaded = try? StyleConfig.load(name: env) {
                return loaded
            }
            // 2. Non-color terminal → notty.
            if !terminal.colorEnabled {
                return try StyleConfig.bundled(.notty)
            }
            // 3. Background hint.
            switch terminal.background {
            case .dark:  return try StyleConfig.bundled(.dark)
            case .light: return try StyleConfig.bundled(.light)
            case .none:  return try StyleConfig.bundled(.notty)
            }
        }
    }
}
