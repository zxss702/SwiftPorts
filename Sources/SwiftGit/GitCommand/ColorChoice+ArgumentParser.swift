import ArgumentParser
import ForgeKit

// ForgeKit's `ColorChoice` is a plain value type — ForgeKit carries no
// ArgumentParser dependency so ArgumentParser (and its libc-overlay
// module edges) stays off every SDK library's module graph. GitCommand
// binds `ColorChoice` as an `@Option` (`git diff/status --color`), so it
// declares the `ExpressibleByArgument` conformance here. The protocol's
// `init?(argument:)` requirement is already satisfied by `ColorChoice`
// itself, so this extension is empty. No `@retroactive` needed —
// `ColorChoice` lives in the same package (ForgeKit), just a different
// module.
extension ColorChoice: ExpressibleByArgument {}
