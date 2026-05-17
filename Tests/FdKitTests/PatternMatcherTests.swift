import Foundation
import Testing
@testable import FdKit

@Suite struct PatternMatcherTests {

    @Test func emptyPatternMatchesEverything() throws {
        let m = try PatternMatcher(PatternOptions())
        #expect(m.matches(basename: "foo.txt", relativePath: "a/foo.txt"))
        #expect(m.matches(basename: "bar", relativePath: "bar"))
    }

    @Test func regexAgainstBasename() throws {
        var opts = PatternOptions()
        opts.pattern = "txt$"
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.txt", relativePath: "a/foo.txt"))
        #expect(!m.matches(basename: "foo.md", relativePath: "a/foo.md"))
    }

    @Test func smartCaseLowercaseIsCaseInsensitive() throws {
        var opts = PatternOptions()
        opts.pattern = "foo"
        opts.caseMode = .smartCase
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "FOO.txt", relativePath: "FOO.txt"))
    }

    @Test func smartCaseUppercaseIsCaseSensitive() throws {
        var opts = PatternOptions()
        opts.pattern = "Foo"
        opts.caseMode = .smartCase
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "Foo.txt", relativePath: "Foo.txt"))
        #expect(!m.matches(basename: "foo.txt", relativePath: "foo.txt"))
    }

    @Test func fixedStringEscapesMetachars() throws {
        var opts = PatternOptions()
        opts.pattern = "a.c"
        opts.syntax = .fixedString
        opts.caseMode = .caseSensitive
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "xa.cy", relativePath: "xa.cy"))
        #expect(!m.matches(basename: "abc", relativePath: "abc"))
    }

    @Test func globAgainstBasename() throws {
        var opts = PatternOptions()
        opts.pattern = "*.swift"
        opts.syntax = .glob
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.swift", relativePath: "a/foo.swift"))
        #expect(!m.matches(basename: "foo.txt", relativePath: "a/foo.txt"))
    }

    @Test func fullPathSwitchUsesRelativePath() throws {
        var opts = PatternOptions()
        opts.pattern = "src/.*\\.swift"
        opts.matchFullPath = true
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.swift", relativePath: "src/foo.swift"))
        #expect(!m.matches(basename: "foo.swift", relativePath: "lib/foo.swift"))
    }

    @Test func extensionFilterAcceptsExtensionOnly() throws {
        var opts = PatternOptions()
        opts.extensions = ["swift"]
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "foo.swift", relativePath: "foo.swift"))
        #expect(!m.matches(basename: "foo.txt", relativePath: "foo.txt"))
    }

    @Test func extensionFilterIsCaseInsensitive() throws {
        var opts = PatternOptions()
        opts.extensions = ["SWIFT"]
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "Foo.swift", relativePath: "Foo.swift"))
    }

    @Test func compoundExtensionMatchTarGz() throws {
        var opts = PatternOptions()
        opts.extensions = ["tar.gz"]
        let m = try PatternMatcher(opts)
        #expect(m.matches(basename: "backup.tar.gz",
                          relativePath: "backup.tar.gz"))
        #expect(!m.matches(basename: "backup.zip",
                           relativePath: "backup.zip"))
    }

    @Test func invalidRegexThrows() {
        var opts = PatternOptions()
        opts.pattern = "("
        opts.caseMode = .caseSensitive
        #expect(throws: FdPatternError.self) {
            _ = try PatternMatcher(opts)
        }
    }

    // MARK: - highlightRange

    @Test func highlightRangeAgainstBasename() throws {
        var opts = PatternOptions()
        opts.pattern = "\\.swift$"
        opts.caseMode = .caseSensitive
        let m = try PatternMatcher(opts)

        let path = "src/foo.swift"
        let range = m.highlightRange(in: path)
        #expect(range != nil)
        if let range {
            #expect(String(path[range]) == ".swift")
        }
    }

    @Test func highlightRangeHonorsFullPath() throws {
        var opts = PatternOptions()
        opts.pattern = "src/foo"
        opts.matchFullPath = true
        opts.caseMode = .caseSensitive
        let m = try PatternMatcher(opts)

        let path = "src/foo.swift"
        let range = m.highlightRange(in: path)
        #expect(range != nil)
        if let range {
            #expect(String(path[range]) == "src/foo")
        }
    }

    @Test func highlightRangeReturnsNilForEmptyPattern() throws {
        let m = try PatternMatcher(PatternOptions())
        #expect(m.highlightRange(in: "anything") == nil)
    }

    @Test func highlightRangeReturnsNilWhenNoMatch() throws {
        var opts = PatternOptions()
        opts.pattern = "foo"
        opts.caseMode = .caseSensitive
        let m = try PatternMatcher(opts)
        // Basename match against "x.txt" — `foo` doesn't appear.
        #expect(m.highlightRange(in: "src/x.txt") == nil)
    }

    @Test func highlightRangeIgnoresTrailingSlashInBasenameMatch() throws {
        var opts = PatternOptions()
        opts.pattern = "^sub$"
        opts.caseMode = .caseSensitive
        let m = try PatternMatcher(opts)
        // Printer adds a trailing `/` to dir entries. The basename
        // regex should still match without the `/` leaking in.
        let range = m.highlightRange(in: "parent/sub/")
        #expect(range != nil)
        if let range {
            #expect(String("parent/sub/"[range]) == "sub")
        }
    }

    @Test func highlightRangeRespectsSmartCase() throws {
        var opts = PatternOptions()
        opts.pattern = "readme"
        opts.caseMode = .smartCase
        let m = try PatternMatcher(opts)
        let range = m.highlightRange(in: "doc/README.md")
        #expect(range != nil)
        if let range {
            #expect(String("doc/README.md"[range]) == "README")
        }
    }
}
