import Foundation

/// Loads JSON fixture files from `Tests/SwiftGHCoreTests/Fixtures/`.
enum FixtureLoader {
    static func data(_ name: String) throws -> Data {
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
        guard let url else {
            throw NSError(
                domain: "FixtureLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Fixture \(name).json not found. " +
                    "Add it under Tests/SwiftGHCoreTests/Fixtures/."])
        }
        return try Data(contentsOf: url)
    }
}
