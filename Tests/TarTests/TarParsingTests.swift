#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import Foundation
import Testing
@testable import TarCommand

@Suite struct TarParsingTests {
    @Test func parsesCreateGzipped() throws {
        let cmd = try TarCommand.parse(["-czf", "out.tgz", "dir1", "dir2"])
        #expect(cmd.create)
        #expect(cmd.gzip)
        #expect(!cmd.extract)
        #expect(!cmd.list)
        #expect(cmd.file == "out.tgz")
        #expect(cmd.args == ["dir1", "dir2"])
    }

    @Test func parsesExtractWithChangeDir() throws {
        let cmd = try TarCommand.parse(["-xzf", "in.tgz", "-C", "/tmp"])
        #expect(cmd.extract)
        #expect(cmd.gzip)
        #expect(cmd.changeDir == "/tmp")
        #expect(cmd.file == "in.tgz")
    }

    @Test func parsesListVerbose() throws {
        let cmd = try TarCommand.parse(["-tvf", "x.tar"])
        #expect(cmd.list)
        #expect(cmd.verbose)
        #expect(cmd.file == "x.tar")
    }

    @Test func parsesStripComponents() throws {
        let cmd = try TarCommand.parse([
            "-xf", "in.tar", "--strip-components", "1", "-C", "out"])
        #expect(cmd.extract)
        #expect(cmd.stripComponents == 1)
        #expect(cmd.changeDir == "out")
    }

    @Test func rejectsConflictingModes() {
        #expect(throws: (any Error).self) {
            var cmd = try TarCommand.parse(["-cxf", "x.tar", "y"])
            try cmd.run()
        }
    }
}

#endif  // !os(Android)
