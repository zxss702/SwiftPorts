import Foundation
import Testing
@testable import FdKit

@Suite struct LsColorsTests {

    // MARK: - Parsing

    @Test func parsesIndicatorAndSuffix() {
        let c = LsColors(spec: "di=01;34:*.swift=38;5;202:ex=01;32")
        #expect(c.code(forBasename: "src",
                       isDirectory: true,
                       isSymlink: false,
                       isRegularFile: false,
                       posixPermissions: nil,
                       fileType: nil) == "01;34")
        #expect(c.code(forBasename: "a.swift",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: nil,
                       fileType: nil) == "38;5;202")
    }

    @Test func suffixMatchIsCaseInsensitive() {
        let c = LsColors(spec: "*.swift=01;33")
        #expect(c.code(forBasename: "Foo.SWIFT",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: nil,
                       fileType: nil) == "01;33")
    }

    @Test func compoundExtensionMatches() {
        let c = LsColors(spec: "*.tar.gz=01;31")
        #expect(c.code(forBasename: "backup.tar.gz",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: nil,
                       fileType: nil) == "01;31")
        // Plain `.gz` shouldn't match the `.tar.gz` rule.
        #expect(c.code(forBasename: "foo.gz",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: nil,
                       fileType: nil) != "01;31")
    }

    @Test func emptySpecYieldsNoCodes() {
        let c = LsColors(spec: "")
        #expect(c.code(forBasename: "anything",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: nil,
                       fileType: nil) == nil)
    }

    @Test func malformedEntriesAreSkipped() {
        // No `=`, empty key, empty value — all dropped silently.
        let c = LsColors(spec: ":di:=01;34:*.swift=:fi=37")
        #expect(c.code(forBasename: "anything",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: nil,
                       fileType: nil) == "37")
        #expect(c.code(forBasename: "src",
                       isDirectory: true,
                       isSymlink: false,
                       isRegularFile: false,
                       posixPermissions: nil,
                       fileType: nil) == nil)
    }

    // MARK: - Indicator precedence

    @Test func symlinkBeatsDirectoryWhenSymlinkSet() {
        let c = LsColors(spec: "di=01;34:ln=01;36")
        // An entry can be both a symlink and resolve to a directory —
        // LS_COLORS rules say `ln` wins.
        #expect(c.code(forBasename: "x",
                       isDirectory: true,
                       isSymlink: true,
                       isRegularFile: false,
                       posixPermissions: nil,
                       fileType: nil) == "01;36")
    }

    @Test func setuidWinsOverExecutable() {
        let c = LsColors(spec: "ex=01;32:su=37;41")
        #expect(c.code(forBasename: "x",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: 0o4755,
                       fileType: nil) == "37;41")
    }

    @Test func otherWritableDirectoryPicksOwOverDi() {
        let c = LsColors(spec: "di=01;34:ow=34;42")
        #expect(c.code(forBasename: "x",
                       isDirectory: true,
                       isSymlink: false,
                       isRegularFile: false,
                       posixPermissions: 0o0757,
                       fileType: nil) == "34;42")
    }

    @Test func stickyOtherWritableDirectoryPicksTw() {
        let c = LsColors(spec: "di=01;34:tw=30;42:ow=34;42")
        #expect(c.code(forBasename: "x",
                       isDirectory: true,
                       isSymlink: false,
                       isRegularFile: false,
                       posixPermissions: 0o1757,
                       fileType: nil) == "30;42")
    }

    @Test func executablePicksExWhenNoSetuidOrSetgid() {
        let c = LsColors(spec: "ex=01;32:fi=37")
        #expect(c.code(forBasename: "x",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: 0o0755,
                       fileType: nil) == "01;32")
    }

    @Test func regularFileWithoutSuffixMatchPicksFi() {
        let c = LsColors(spec: "fi=37:*.swift=01;33")
        #expect(c.code(forBasename: "README",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: 0o0644,
                       fileType: nil) == "37")
    }

    // MARK: - Wrap helper

    @Test func wrapAppliesAnsiEscapes() {
        let c = LsColors(spec: "di=01;34")
        let wrapped = c.wrap("src", with: "01;34")
        #expect(wrapped == "\u{1B}[01;34msrc\u{1B}[0m")
    }

    @Test func wrapUsesCustomResetWhenRsSet() {
        let c = LsColors(spec: "rs=22:di=01;34")
        let wrapped = c.wrap("src", with: "01;34")
        #expect(wrapped == "\u{1B}[01;34msrc\u{1B}[22m")
    }

    @Test func wrapWithEmptyCodeReturnsUnchanged() {
        let c = LsColors(spec: "")
        #expect(c.wrap("src", with: "") == "src")
    }

    // MARK: - Built-in default

    @Test func defaultSpecHasReasonablePalette() {
        let c = LsColors(spec: LsColors.defaultSpec)
        // Directory → bold blue.
        #expect(c.code(forBasename: "x",
                       isDirectory: true,
                       isSymlink: false,
                       isRegularFile: false,
                       posixPermissions: 0o0755,
                       fileType: nil) == "01;34")
        // Symlink → bold cyan.
        #expect(c.code(forBasename: "x",
                       isDirectory: false,
                       isSymlink: true,
                       isRegularFile: false,
                       posixPermissions: nil,
                       fileType: nil) == "01;36")
        // Executable → bold green.
        #expect(c.code(forBasename: "x",
                       isDirectory: false,
                       isSymlink: false,
                       isRegularFile: true,
                       posixPermissions: 0o0755,
                       fileType: nil) == "01;32")
    }
}
