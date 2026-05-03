import Foundation

public struct Reactions: Codable, Sendable {
    public let totalCount: Int
    public let plus1: Int
    public let minus1: Int
    public let laugh: Int
    public let hooray: Int
    public let confused: Int
    public let heart: Int
    public let rocket: Int
    public let eyes: Int
    public let url: URL?

    // `convertFromSnakeCase` maps `total_count` → `totalCount`
    // before matching, so use the converted form here. `+1` / `-1`
    // contain no underscores and pass through verbatim.
    enum CodingKeys: String, CodingKey {
        case totalCount
        case plus1 = "+1"
        case minus1 = "-1"
        case laugh, hooray, confused, heart, rocket, eyes, url
    }
}
