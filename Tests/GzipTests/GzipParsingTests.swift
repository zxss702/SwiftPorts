#if !os(Android)  // argv-parsing test; ArgumentParser trips the Android explicit-module scanner
import Foundation
import Testing
@testable import GzipCommand

@Suite struct GzipParsingTests {
    @Test func gzipParsesCommonFlags() throws {
        let cmd = try Gzip.parse(["-9", "-k", "-c", "file.txt"])
        #expect(cmd.level9)
        #expect(cmd.keep)
        #expect(cmd.stdout)
        #expect(!cmd.decompress)
        #expect(cmd.files == ["file.txt"])
    }

    @Test func gzipDecompressFlag() throws {
        let cmd = try Gzip.parse(["-d", "data.gz"])
        #expect(cmd.decompress)
        #expect(cmd.files == ["data.gz"])
    }

    @Test func gunzipDefaultsToDecompress() throws {
        // Gunzip doesn't expose -d at all — it's always decompress.
        let cmd = try Gunzip.parse(["-c", "data.gz"])
        #expect(cmd.stdout)
        #expect(cmd.files == ["data.gz"])
    }

    @Test func zcatParsesFiles() throws {
        let cmd = try Zcat.parse(["a.gz", "b.gz"])
        #expect(cmd.files == ["a.gz", "b.gz"])
    }

    @Test func gzipAcceptsStdinSentinel() throws {
        let cmd = try Gzip.parse(["-c", "-"])
        #expect(cmd.files == ["-"])
    }
}

#endif  // !os(Android)
