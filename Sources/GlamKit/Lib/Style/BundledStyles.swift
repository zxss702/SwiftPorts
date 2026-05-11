import Foundation

/// Built-in style identifiers — same set as glamour's `DefaultStyles`
/// minus `pink` / `dracula` / `tokyo-night`. The first four cover
/// every gh/glab call site.
public enum BundledStyle: String, Sendable, CaseIterable {
    case dark
    case light
    case notty
    case ascii

    /// Subset of glamour styles we ship verbatim JSON for.
    public var resourceName: String { rawValue }
}

public enum BundledStyleError: Error, CustomStringConvertible, Sendable {
    case resourceNotFound(String)
    case decodeFailed(String, underlying: Error)

    public var description: String {
        switch self {
        case .resourceNotFound(let n):
            return "GlamKit: bundled style '\(n)' not found in module resources"
        case .decodeFailed(let n, let e):
            return "GlamKit: bundled style '\(n)' failed to decode: \(e)"
        }
    }
}

extension StyleConfig {
    /// Load one of the four bundled styles from the module bundle.
    /// Resource JSON layout matches glamour's `styles/*.json` byte-
    /// for-byte, so users can mix our bundled set with their own
    /// copies of upstream's pink / dracula / tokyo-night without
    /// surprise.
    public static func bundled(_ style: BundledStyle) throws -> StyleConfig {
        guard let url = Bundle.module.url(
            forResource: style.resourceName,
            withExtension: "json"
        ) else {
            throw BundledStyleError.resourceNotFound(style.rawValue)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(StyleConfig.self, from: data)
        } catch {
            throw BundledStyleError.decodeFailed(style.rawValue, underlying: error)
        }
    }

    /// Loads a style by name. Tries the bundled set first, then falls
    /// back to reading `name` as a filesystem path (same behavior as
    /// glamour's `WithStylePath`). Returns the dark style on miss to
    /// match upstream's `getEnvironmentStyle` fallback.
    public static func load(name: String) throws -> StyleConfig {
        if let bundled = BundledStyle(rawValue: name) {
            return try StyleConfig.bundled(bundled)
        }
        let url = URL(fileURLWithPath: name)
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(StyleConfig.self, from: data)
        } catch {
            throw BundledStyleError.decodeFailed(name, underlying: error)
        }
    }
}
