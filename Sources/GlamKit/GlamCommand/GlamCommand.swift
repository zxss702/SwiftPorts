import ArgumentParser
import Foundation
import GlamKit
import ShellKit

/// `glam [OPTIONS] [FILE...]` — render Markdown to ANSI.
///
/// A pure-Swift port of the rendering side of charmbracelet/glamour.
/// Output mirrors what `gh pr view`, `glab mr view`, and `glow` emit:
/// headings, lists, links (OSC 8 when the terminal supports it),
/// blockquotes, code blocks, tables, emphasis. Honors `GLAMOUR_STYLE`
/// and `GH_MDWIDTH` env vars, and falls back to a non-color "notty"
/// style when stdout isn't a terminal.
///
/// Reads stdin when no file is given:
///   `echo "# Hi" | glam`
///   `glam README.md`
///   `glam --style dark CHANGELOG.md`
public struct Glam: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "glam",
        abstract: "Render Markdown to ANSI."
    )

    @Argument(help: "Markdown files. Defaults to stdin.")
    public var files: [String] = []

    @Option(name: [.short, .long],
            help: "Style: auto, dark, light, notty, ascii, or path to a glamour JSON.")
    public var style: String = "auto"

    @Option(name: [.short, .long],
            help: "Word-wrap width. 0 disables wrapping. Default 80.")
    public var width: Int?

    @Option(name: .long,
            help: "Base URL for resolving relative links.")
    public var baseURL: String?

    public init() {}

    public func run() async throws {
        let renderer = try Renderer(
            style:    Glam.parseStyle(style),
            wordWrap: width,
            baseURL:  baseURL
        )
        let stdin  = Shell.current.stdin
        let stdout = Shell.current.stdout

        if files.isEmpty {
            let input = await stdin.readAllString()
            try emit(renderer.render(input), to: stdout)
            return
        }

        for path in files {
            let url = Shell.resolve(path)
            try await Shell.authorize(url)
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            try emit(renderer.render(text), to: stdout)
        }
    }

    private func emit(_ s: String, to out: OutputSink) throws {
        var output = s
        if !output.hasSuffix("\n") { output += "\n" }
        out.write(Data(output.utf8))
    }

    /// Parse the `-s/--style` flag. `auto` / `dark` / `light` /
    /// `notty` / `ascii` are bundled; anything else is treated as a
    /// path to a glamour-shaped JSON file.
    static func parseStyle(_ raw: String) -> GlamKit.Glam.Style {
        switch raw.lowercased() {
        case "auto", "":     return .auto
        case "dark":         return .bundled(.dark)
        case "light":        return .bundled(.light)
        case "notty", "none": return .bundled(.notty)
        case "ascii":        return .bundled(.ascii)
        default:
            // Try loading as a path — fall back to .auto on miss
            // rather than failing the command (gh/glab don't error
            // when `GLAMOUR_STYLE` points at a missing file either).
            if let config = try? StyleConfig.load(name: raw) {
                return .custom(config)
            }
            return .auto
        }
    }
}
