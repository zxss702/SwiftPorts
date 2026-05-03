import Foundation
import HTTPTypes
import HTTPTypesFoundation
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GitHub OAuth Device Flow client.
///
/// The device flow trades a browser+localhost listener (the
/// "web" flow) for a 6-character user code the human types into
/// `verification_uri` themselves. Best fit for SwiftGH's sandboxed /
/// embedded targets where launching a browser or binding a port may
/// be impossible.
///
/// Flow per RFC 8628 + GitHub's docs:
///   1. POST /login/device/code with client_id + scope
///   2. Show `user_code`; user opens `verification_uri` and types it in
///   3. Poll POST /login/oauth/access_token until granted, denied,
///      expired, or rate-limited
///
/// Caller responsibilities:
///   - Display the user code + URL
///   - Decide when to give up vs keep polling
///
/// This actor handles only the HTTP plumbing; the CLI's eventual
/// `gh auth login` will own the UI side.
public actor OAuthDeviceFlow {
    public let clientID: String
    public let host: String
    private let session: URLSession
    private let logger: Logger

    /// The same OAuth app ID Go gh uses. **Do not reuse for a fork or
    /// a separate product** — register your own at
    /// `https://github.com/settings/applications/new`. Surfaced here
    /// only so the device flow has a working default while SwiftGH
    /// is in pre-release.
    public static let ghCLIClientID = "178c6fc778ccc68e1d6a"

    public init(
        clientID: String,
        host: String = "github.com",
        session: URLSession = .shared,
        logger: Logger = Loggers.auth
    ) {
        self.clientID = clientID
        self.host = host
        self.session = session
        self.logger = logger
    }

    // MARK: Step 1: Request a device + user code

    public func requestDeviceCode(scopes: [String]) async throws -> DeviceCode {
        var request = HTTPRequest(method: .post, url: deviceCodeURL)
        request.headerFields[.accept] = "application/json"
        request.headerFields[.contentType] = "application/x-www-form-urlencoded"

        let body = formEncode([
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ])
        let bodyData = Data(body.utf8)

        logger.debug("Device flow: requesting device code (scopes: \(scopes))")
        let (data, response) = try await session.upload(for: request, from: bodyData)
        try check2xx(status: response.status.code, body: data, url: deviceCodeURL)
        return try JSONDecoder.gitHub().decode(DeviceCode.self, from: data)
    }

    // MARK: Step 2: User visits verification_uri (no API)

    // MARK: Step 3: Poll for the access token

    /// Poll until the user grants/denies, the code expires, or
    /// `deadline` passes. Honors `slow_down` by widening the
    /// interval. Returns the token on success.
    public func pollForToken(
        deviceCode: DeviceCode,
        deadline: Date? = nil
    ) async throws -> AccessToken {
        var interval = TimeInterval(deviceCode.interval)
        let actualDeadline = deadline
            ?? Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))

        while Date() < actualDeadline {
            try? await Task.sleep(for: .seconds(interval))
            do {
                return try await exchangeOnce(deviceCode: deviceCode.deviceCode)
            } catch let OAuthDeviceFlowError.authorizationPending {
                continue
            } catch let OAuthDeviceFlowError.slowDown {
                // Server asked us to back off; bump interval per spec.
                interval += 5
                continue
            } catch {
                throw error
            }
        }
        throw OAuthDeviceFlowError.expiredToken
    }

    public func exchangeOnce(deviceCode: String) async throws -> AccessToken {
        var request = HTTPRequest(method: .post, url: accessTokenURL)
        request.headerFields[.accept] = "application/json"
        request.headerFields[.contentType] = "application/x-www-form-urlencoded"

        let body = formEncode([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        let bodyData = Data(body.utf8)

        let (data, response) = try await session.upload(for: request, from: bodyData)
        guard (200..<300).contains(response.status.code) else {
            throw OAuthDeviceFlowError.networkError(
                status: response.status.code,
                body: String(data: data, encoding: .utf8) ?? "")
        }

        // GitHub returns 200 with an `error` field for in-flight states.
        if let envelope = try? JSONDecoder.gitHub().decode(
            AccessTokenErrorEnvelope.self, from: data),
           let error = envelope.error {
            switch error {
            case "authorization_pending": throw OAuthDeviceFlowError.authorizationPending
            case "slow_down": throw OAuthDeviceFlowError.slowDown
            case "expired_token": throw OAuthDeviceFlowError.expiredToken
            case "access_denied": throw OAuthDeviceFlowError.accessDenied
            case "incorrect_device_code", "incorrect_client_credentials":
                throw OAuthDeviceFlowError.invalidGrant(reason: error)
            default:
                throw OAuthDeviceFlowError.unknownError(
                    code: error,
                    description: envelope.errorDescription)
            }
        }

        return try JSONDecoder.gitHub().decode(AccessToken.self, from: data)
    }

    /// Run the entire flow end-to-end: request a device code, surface
    /// it via `display`, then poll until grant or timeout.
    public func authorize(
        scopes: [String],
        display: @Sendable (DeviceCode) async -> Void
    ) async throws -> AccessToken {
        let code = try await requestDeviceCode(scopes: scopes)
        await display(code)
        return try await pollForToken(deviceCode: code)
    }

    // MARK: URLs

    private var deviceCodeURL: URL {
        URL(string: "https://\(host)/login/device/code")!
    }
    private var accessTokenURL: URL {
        URL(string: "https://\(host)/login/oauth/access_token")!
    }

    // MARK: Helpers

    private func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = percentEncode(key)
            let v = percentEncode(value)
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? s
    }

    private func check2xx(status: Int, body: Data, url: URL) throws {
        guard !(200..<300).contains(status) else { return }
        throw OAuthDeviceFlowError.networkError(
            status: status, body: String(data: body, encoding: .utf8) ?? "")
    }
}

private extension CharacterSet {
    /// RFC 3986 safe characters for x-www-form-urlencoded values.
    /// `urlQueryAllowed` keeps `+ &`; we exclude both.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
