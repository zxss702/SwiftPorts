import Foundation
import RipgrepKit

/// Pattern-matching error surface. Distinct name from RipgrepKit's
/// `PatternError` so a caller that imports both kits doesn't get a
/// type-lookup ambiguity.
public struct FdPatternError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// Compiles a `PatternOptions` value into a callable matcher. The
/// matcher takes a (basename, relativePath) pair and answers whether
/// the entry should be emitted.
///
/// Upstream fd implements three pattern syntaxes — regex (default),
/// shell glob (`-g`), and literal substring (`-F`). All three are
/// reduced to an `NSRegularExpression` here so the per-entry path
/// only walks one engine.
public struct PatternMatcher: Sendable {

    private let regex: NSRegularExpression?
    private let matchFullPath: Bool
    private let extensions: [String]

    public init(_ options: PatternOptions) throws {
        self.matchFullPath = options.matchFullPath
        self.extensions = options.extensions.map { $0.lowercased() }

        // An empty pattern matches every entry (fd's no-pattern mode).
        if options.pattern.isEmpty {
            self.regex = nil
            return
        }

        let body: String
        switch options.syntax {
        case .regex:
            body = options.pattern
        case .fixedString:
            body = NSRegularExpression.escapedPattern(for: options.pattern)
        case .glob:
            // Reuse the gitignore glob compiler from RipgrepKit. For
            // fd, globs are anchored to the basename when
            // `--full-path` is off — the GitignoreGlob compile path
            // accepts a flag for that.
            body = GitignoreGlob.compile(options.pattern,
                                         anchored: options.matchFullPath)
            // GitignoreGlob.compile produces a fully-anchored regex
            // (`^…$`). Skip the case-folding insertion below by
            // building the NSRegularExpression directly.
            var regexOptions: NSRegularExpression.Options = []
            switch options.caseMode {
            case .ignoreCase:
                regexOptions.insert(.caseInsensitive)
            case .caseSensitive:
                break
            case .smartCase:
                if !options.pattern.contains(where: { $0.isUppercase }) {
                    regexOptions.insert(.caseInsensitive)
                }
            }
            do {
                self.regex = try NSRegularExpression(pattern: body,
                                                     options: regexOptions)
            } catch {
                throw FdPatternError(message: "invalid glob '\(options.pattern)': \(error.localizedDescription)")
            }
            return
        }

        var regexOptions: NSRegularExpression.Options = []
        switch options.caseMode {
        case .ignoreCase:
            regexOptions.insert(.caseInsensitive)
        case .caseSensitive:
            break
        case .smartCase:
            if !options.pattern.contains(where: { $0.isUppercase }) {
                regexOptions.insert(.caseInsensitive)
            }
        }

        do {
            self.regex = try NSRegularExpression(pattern: body,
                                                 options: regexOptions)
        } catch {
            throw FdPatternError(message: "invalid pattern '\(options.pattern)': \(error.localizedDescription)")
        }
    }

    /// True if this entry should be emitted given its basename and
    /// relative path. The caller passes both because fd matches the
    /// basename by default and the full path under `--full-path`.
    public func matches(basename: String, relativePath: String) -> Bool {
        // Extension filter — applies regardless of pattern, fd-style.
        if !extensions.isEmpty {
            let ext = (basename as NSString).pathExtension.lowercased()
            // `*.tar.gz` style: also try the compound extension.
            var ok = extensions.contains(ext)
            if !ok {
                // fd matches longest-extension first for tarballs etc.
                for candidate in extensions {
                    if basename.lowercased().hasSuffix("." + candidate) {
                        ok = true
                        break
                    }
                }
            }
            if !ok { return false }
        }
        guard let regex else { return true }
        let target = matchFullPath ? relativePath : basename
        let range = NSRange(target.startIndex..., in: target)
        return regex.firstMatch(in: target,
                                options: [],
                                range: range) != nil
    }
}
