import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct RepositoryReferenceTests {
    @Test func parsesOwnerName() throws {
        let ref = try RepositoryReference(parsing: "cli/cli")
        #expect(ref.owner == "cli")
        #expect(ref.name == "cli")
        #expect(ref.slug == "cli/cli")
    }

    @Test func parsesHostOwnerName() throws {
        let ref = try RepositoryReference(parsing: "github.com/cli/cli")
        #expect(ref.owner == "cli")
        #expect(ref.name == "cli")
    }

    @Test func rejectsMalformed() {
        #expect(throws: RepositoryReferenceParseError.self) {
            _ = try RepositoryReference(parsing: "justaword")
        }
        #expect(throws: RepositoryReferenceParseError.self) {
            _ = try RepositoryReference(parsing: "/missing-owner")
        }
        #expect(throws: RepositoryReferenceParseError.self) {
            _ = try RepositoryReference(parsing: "")
        }
    }
}
