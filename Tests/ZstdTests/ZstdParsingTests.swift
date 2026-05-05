// libbz2/liblzma/libzstd are not in the iOS / tvOS / watchOS / visionOS
// SDK. Gate the whole module to platforms where the system library is
// available; iOS support requires vendoring sources.
#if os(macOS) || os(Linux) || os(Windows)

import Foundation
import Testing
@testable import ZstdCommand

@Suite struct ZstdParsingTests {
    @Test func zstdParsesCommonFlags() throws {
        let cmd = try Zstd.parse(["-9", "-k", "-c", "file.txt"])
        #expect(cmd.level9)
        #expect(cmd.keep)
        #expect(cmd.stdout)
        #expect(!cmd.decompress)
        #expect(cmd.files == ["file.txt"])
    }

    @Test func zstdDecompressFlag() throws {
        let cmd = try Zstd.parse(["-d", "data.zst"])
        #expect(cmd.decompress)
        #expect(cmd.files == ["data.zst"])
    }

    @Test func unzstdDefaultsToDecompress() throws {
        let cmd = try Unzstd.parse(["-c", "data.zst"])
        #expect(cmd.stdout)
        #expect(cmd.files == ["data.zst"])
    }

    @Test func zstdcatParsesFiles() throws {
        let cmd = try Zstdcat.parse(["a.zst", "b.zst"])
        #expect(cmd.files == ["a.zst", "b.zst"])
    }

    @Test func zstdAcceptsStdinSentinel() throws {
        let cmd = try Zstd.parse(["-c", "-"])
        #expect(cmd.files == ["-"])
    }
}

#endif // platform gate
