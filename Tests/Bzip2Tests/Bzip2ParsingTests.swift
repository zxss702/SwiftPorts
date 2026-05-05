// libbz2/liblzma/libzstd are not in the iOS / tvOS / watchOS / visionOS
// SDK. Gate the whole module to platforms where the system library is
// available; iOS support requires vendoring sources.
#if os(macOS) || os(Linux) || os(Windows)

import Foundation
import Testing
@testable import Bzip2Command

@Suite struct Bzip2ParsingTests {
    @Test func bzip2ParsesCommonFlags() throws {
        let cmd = try Bzip2.parse(["-9", "-k", "-c", "file.txt"])
        #expect(cmd.level9)
        #expect(cmd.keep)
        #expect(cmd.stdout)
        #expect(!cmd.decompress)
        #expect(cmd.files == ["file.txt"])
    }

    @Test func bzip2DecompressFlag() throws {
        let cmd = try Bzip2.parse(["-d", "data.bz2"])
        #expect(cmd.decompress)
        #expect(cmd.files == ["data.bz2"])
    }

    @Test func bunzip2DefaultsToDecompress() throws {
        let cmd = try Bunzip2.parse(["-c", "data.bz2"])
        #expect(cmd.stdout)
        #expect(cmd.files == ["data.bz2"])
    }

    @Test func bzcatParsesFiles() throws {
        let cmd = try Bzcat.parse(["a.bz2", "b.bz2"])
        #expect(cmd.files == ["a.bz2", "b.bz2"])
    }

    @Test func bzip2AcceptsStdinSentinel() throws {
        let cmd = try Bzip2.parse(["-c", "-"])
        #expect(cmd.files == ["-"])
    }
}

#endif // platform gate
