import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct GistDecodingTests {
    @Test func decodesOctocatHelloWorld() throws {
        let data = try FixtureLoader.data("gist_sample")
        let gist = try JSONDecoder.gitHub().decode(Gist.self, from: data)

        #expect(gist.id == "6cad326836d38bd3a7ae")
        #expect(gist.description == "Hello world!")
        #expect(gist.public == true)
        #expect(gist.owner?.login == "octocat")
        #expect(gist.user == nil)

        let file = try #require(gist.files["hello_world.rb"])
        #expect(file.language == "Ruby")
        #expect(file.size == 175)
        #expect(file.content?.contains("class HelloWorld") == true)
    }
}
