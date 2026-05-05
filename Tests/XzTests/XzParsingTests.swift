// libbz2/liblzma/libzstd are not in the iOS / tvOS / watchOS / visionOS
// SDK. Gate the whole module to platforms where the system library is
// available; iOS support requires vendoring sources.
#if canImport(Compression) || os(Linux) || os(Windows)

import Foundation
import Testing
@testable import XzCommand

@Suite struct XzParsingTests {
    @Test func xzParsesCommonFlags() throws {
        let cmd = try Xz.parse(["-9", "-k", "-c", "file.txt"])
        #expect(cmd.level9)
        #expect(cmd.keep)
        #expect(cmd.stdout)
        #expect(!cmd.decompress)
        #expect(cmd.files == ["file.txt"])
    }

    @Test func xzDecompressFlag() throws {
        let cmd = try Xz.parse(["-d", "data.xz"])
        #expect(cmd.decompress)
        #expect(cmd.files == ["data.xz"])
    }

    @Test func unxzDefaultsToDecompress() throws {
        let cmd = try Unxz.parse(["-c", "data.xz"])
        #expect(cmd.stdout)
        #expect(cmd.files == ["data.xz"])
    }

    @Test func xzcatParsesFiles() throws {
        let cmd = try Xzcat.parse(["a.xz", "b.xz"])
        #expect(cmd.files == ["a.xz", "b.xz"])
    }

    @Test func xzAcceptsStdinSentinel() throws {
        let cmd = try Xz.parse(["-c", "-"])
        #expect(cmd.files == ["-"])
    }

    @Test func xzAcceptsExtremeFlag() throws {
        let cmd = try Xz.parse(["-9e", "file.txt"])
        #expect(cmd.level9)
        #expect(cmd.extreme)
    }
}

#endif // platform gate
