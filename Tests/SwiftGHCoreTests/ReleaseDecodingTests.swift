import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct ReleaseDecodingTests {
    @Test func decodesCliLatest() throws {
        let data = try FixtureLoader.data("release_cli_latest")
        let release = try JSONDecoder.gitHub().decode(Release.self, from: data)

        #expect(release.tagName.hasPrefix("v"))
        #expect(release.draft == false)
        #expect(release.author.type == .bot)
        #expect(release.author.login == "github-actions[bot]")
        #expect(!release.assets.isEmpty)
        #expect(release.htmlUrl.host == "github.com")

        let firstAsset = try #require(release.assets.first)
        #expect(firstAsset.size > 0)
        #expect(firstAsset.browserDownloadUrl.absoluteString.contains("/releases/download/"))
    }
}
