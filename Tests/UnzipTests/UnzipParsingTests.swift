#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import ArgumentParser
import Foundation
import Testing
@testable import UnzipCommand

@Suite struct UnzipParsingTests {
    @Test func parsesBareArchive() throws {
        let cmd = try UnzipCommand.parse(["archive.zip"])
        #expect(cmd.archive == "archive.zip")
        #expect(cmd.destination == ".")
        #expect(cmd.list == false)
        #expect(cmd.test == false)
        #expect(cmd.pipe == false)
    }

    @Test func parsesDestination() throws {
        let cmd = try UnzipCommand.parse(["archive.zip", "-d", "/tmp/out"])
        #expect(cmd.destination == "/tmp/out")
    }

    @Test func parsesListAndVerbose() throws {
        let cmd = try UnzipCommand.parse(["archive.zip", "-lv"])
        #expect(cmd.list == true)
        #expect(cmd.verbose == true)
    }

    @Test func parsesIncludeAndExcludePatterns() throws {
        let cmd = try UnzipCommand.parse([
            "archive.zip", "*.swift", "*.md", "-x", "Tests/*", "-x", "*.private",
        ])
        #expect(cmd.patterns == ["*.swift", "*.md"])
        #expect(cmd.excludePatterns == ["Tests/*", "*.private"])
    }

    @Test func parsesShortFlagsCombined() throws {
        // Argument-Parser doesn't combine -lv (a single token), but
        // it does accept them as separate flags.
        let cmd = try UnzipCommand.parse(["archive.zip", "-l", "-v"])
        #expect(cmd.list)
        #expect(cmd.verbose)
    }
}

#endif  // !os(Android)
