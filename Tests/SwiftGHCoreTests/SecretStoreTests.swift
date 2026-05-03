import Foundation
import Testing
@testable import SwiftGHCore

@Suite struct InMemorySecretStoreTests {
    @Test func roundTrip() async throws {
        let store = InMemorySecretStore()
        try await store.set(service: "com.swiftgh.test", account: "github.com", secret: "abc")
        let got = try await store.get(service: "com.swiftgh.test", account: "github.com")
        #expect(got == "abc")
    }

    @Test func returnsNilForMissing() async throws {
        let store = InMemorySecretStore()
        let got = try await store.get(service: "x", account: "y")
        #expect(got == nil)
    }

    @Test func overwrites() async throws {
        let store = InMemorySecretStore()
        try await store.set(service: "s", account: "a", secret: "v1")
        try await store.set(service: "s", account: "a", secret: "v2")
        #expect(try await store.get(service: "s", account: "a") == "v2")
    }

    @Test func deletes() async throws {
        let store = InMemorySecretStore()
        try await store.set(service: "s", account: "a", secret: "v")
        try await store.delete(service: "s", account: "a")
        #expect(try await store.get(service: "s", account: "a") == nil)
    }

    @Test func deleteMissingIsNoOp() async throws {
        let store = InMemorySecretStore()
        try await store.delete(service: "s", account: "a")
    }

    @Test func separatesByServiceAndAccount() async throws {
        let store = InMemorySecretStore()
        try await store.set(service: "a", account: "x", secret: "1")
        try await store.set(service: "b", account: "x", secret: "2")
        try await store.set(service: "a", account: "y", secret: "3")
        #expect(try await store.get(service: "a", account: "x") == "1")
        #expect(try await store.get(service: "b", account: "x") == "2")
        #expect(try await store.get(service: "a", account: "y") == "3")
    }
}

#if canImport(Security)
/// Opt-in: actually writes to the user's keychain. Skipped without
/// SWIFTGH_KEYCHAIN_TESTS=1 because it leaves a transient entry until
/// the test cleans up.
@Suite(
    .disabled(if: ProcessInfo.processInfo.environment["SWIFTGH_KEYCHAIN_TESTS"] == nil,
              "Set SWIFTGH_KEYCHAIN_TESTS=1 to exercise the real Keychain.")
)
struct KeychainSecretStoreTests {
    @Test func realKeychainRoundTrip() async throws {
        let store = KeychainSecretStore()
        let service = "com.swiftgh.tests.\(UUID().uuidString)"
        let account = "github.com"
        defer {
            Task {
                try? await store.delete(service: service, account: account)
            }
        }
        try await store.set(service: service, account: account, secret: "secret-value")
        let got = try await store.get(service: service, account: account)
        #expect(got == "secret-value")
        try await store.delete(service: service, account: account)
        #expect(try await store.get(service: service, account: account) == nil)
    }
}
#endif
