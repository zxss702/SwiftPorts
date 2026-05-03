import Foundation
import Synchronization

/// Thread-safe in-process secret store. Default for tests and for
/// embedders that don't want any disk persistence.
///
/// Values are dropped when the process exits. NEVER use as a "real"
/// store — gh-style commands assume secrets survive across runs.
public final class InMemorySecretStore: SecretStore {
    private struct Key: Hashable {
        let service: String
        let account: String
    }
    private let storage = Mutex<[Key: String]>([:])

    public init() {}

    public func get(service: String, account: String) async throws -> String? {
        storage.withLock { $0[Key(service: service, account: account)] }
    }

    public func set(service: String, account: String, secret: String) async throws {
        storage.withLock { $0[Key(service: service, account: account)] = secret }
    }

    public func delete(service: String, account: String) async throws {
        storage.withLock { $0[Key(service: service, account: account)] = nil }
    }
}
