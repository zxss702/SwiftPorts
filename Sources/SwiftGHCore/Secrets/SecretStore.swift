import Foundation

/// Persistent credential storage abstracted behind a protocol so the
/// embedder picks the backing store that fits their environment:
///
///   - macOS / iOS app:    `KeychainSecretStore` (Security framework)
///   - Linux server:       a libsecret-backed impl (future port)
///   - Tests / Playground: `InMemorySecretStore`
///   - Sandboxed iOS / no-store environments:
///     `InMemorySecretStore` (tokens vanish on quit)
///
/// `service` identifies the consumer ("com.swiftgh.gh"), `account` is
/// the per-host identity ("github.com" or "ghe.example.com" + login).
public protocol SecretStore: Sendable {
    func get(service: String, account: String) async throws -> String?
    func set(service: String, account: String, secret: String) async throws
    func delete(service: String, account: String) async throws
}

public enum SecretStoreError: Error, LocalizedError, Sendable {
    case backendUnavailable(reason: String)
    case backendError(status: Int32, message: String)
    case invalidValue

    public var errorDescription: String? {
        switch self {
        case .backendUnavailable(let reason):
            return "Secret store unavailable: \(reason)"
        case .backendError(let status, let message):
            return "Secret store backend error (\(status)): \(message)"
        case .invalidValue:
            return "Stored secret was not valid UTF-8."
        }
    }
}
