import Foundation

extension JSONDecoder {
    /// Pre-configured decoder matching the GitHub REST API's wire format.
    ///
    /// - `keyDecodingStrategy = .convertFromSnakeCase`
    ///   `pushed_at` → `pushedAt`, `html_url` → `htmlUrl`, etc.
    /// - `dateDecodingStrategy = .iso8601`
    ///   GitHub returns RFC 3339 like `"2024-01-15T10:30:00Z"`.
    /// - `dataDecodingStrategy = .base64`
    ///   The contents API returns file bodies as base64 strings.
    public static func gitHub() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}

extension JSONEncoder {
    /// Mirror of ``JSONDecoder/gitHub()`` for outbound bodies (POST/PATCH).
    public static func gitHub() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}
