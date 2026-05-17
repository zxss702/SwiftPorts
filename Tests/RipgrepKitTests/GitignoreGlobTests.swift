import Foundation
import Testing
@testable import RipgrepKit

@Suite struct GitignoreGlobTests {

    @Test func literalMatch() throws {
        let g = try GitignoreGlob(pattern: "foo.txt")
        #expect(g.matches("foo.txt", isDirectory: false))
        #expect(g.matches("sub/foo.txt", isDirectory: false))
        #expect(!g.matches("foo.txt.bak", isDirectory: false))
    }

    @Test func starGlob() throws {
        let g = try GitignoreGlob(pattern: "*.log")
        #expect(g.matches("a.log", isDirectory: false))
        #expect(g.matches("dir/a.log", isDirectory: false))
        #expect(!g.matches("a.txt", isDirectory: false))
    }

    @Test func doubleStarGlob() throws {
        let g = try GitignoreGlob(pattern: "build/**/cache")
        #expect(g.matches("build/cache", isDirectory: false))
        #expect(g.matches("build/x/cache", isDirectory: false))
        #expect(g.matches("build/x/y/cache", isDirectory: false))
        #expect(!g.matches("other/cache", isDirectory: false))
    }

    @Test func leadingSlashAnchored() throws {
        let g = try GitignoreGlob(pattern: "/build")
        #expect(g.matches("build", isDirectory: true))
        #expect(g.matches("build/x", isDirectory: false))
        #expect(!g.matches("nested/build", isDirectory: true))
    }

    @Test func trailingSlashDirectoryOnly() throws {
        let g = try GitignoreGlob(pattern: "node_modules/")
        #expect(g.matches("node_modules", isDirectory: true))
        #expect(g.matches("a/node_modules", isDirectory: true))
        // Trailing-slash matches the directory and its contents.
        #expect(g.matches("node_modules", isDirectory: true))
        // But not when the path is a file with that name.
        #expect(!g.matches("node_modules", isDirectory: false))
    }

    @Test func negationStripsLeadingBang() throws {
        let g = try GitignoreGlob(pattern: "!keep.txt")
        #expect(g.isNegation == true)
        #expect(g.matches("keep.txt", isDirectory: false))
    }

    @Test func questionMarkSingleChar() throws {
        let g = try GitignoreGlob(pattern: "a?c")
        #expect(g.matches("abc", isDirectory: false))
        #expect(g.matches("axc", isDirectory: false))
        #expect(!g.matches("ac", isDirectory: false))
    }

    @Test func bracketClass() throws {
        let g = try GitignoreGlob(pattern: "[abc].txt")
        #expect(g.matches("a.txt", isDirectory: false))
        #expect(g.matches("b.txt", isDirectory: false))
        #expect(!g.matches("d.txt", isDirectory: false))
    }

    @Test func caseInsensitiveOption() throws {
        let g = try GitignoreGlob(pattern: "*.LOG", caseInsensitive: true)
        #expect(g.matches("a.log", isDirectory: false))
        #expect(g.matches("A.LOG", isDirectory: false))
    }
}
