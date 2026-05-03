import ArgumentParser
import Foundation
import Testing
@testable import SwiftGHCommand

@Suite struct ApiCommandParsingTests {
    @Test func defaultsToGet() throws {
        let cmd = try ApiCommand.parse(["repos/cli/cli"])
        #expect(cmd.endpoint == "repos/cli/cli")
        #expect(cmd.method == "GET")
        #expect(cmd.fields.isEmpty)
        #expect(cmd.rawFields.isEmpty)
    }

    @Test func acceptsMethodOverride() throws {
        let cmd = try ApiCommand.parse(["-X", "DELETE", "/x"])
        #expect(cmd.method == "DELETE")
    }

    @Test func collectsFields() throws {
        let cmd = try ApiCommand.parse([
            "x", "-F", "title=hi", "-F", "draft=true", "-f", "body=raw",
        ])
        #expect(cmd.fields == ["title=hi", "draft=true"])
        #expect(cmd.rawFields == ["body=raw"])
    }
}
