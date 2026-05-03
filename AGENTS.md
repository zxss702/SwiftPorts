# Agent instructions — SwiftGH

A Swift port of the GitHub CLI ([cli/cli](https://github.com/cli/cli)).
Goal: feature-complete `gh` rewritten in pure Swift, cross-platform
(Mac / Linux / iOS-embeddable), built on Swift Argument Parser, Swift
Testing, and `swift-log`.

The Go reference checkout lives at `~/Developer/Others/cli`. Read it
liberally — every Swift command has a Go counterpart under
`pkg/cmd/<command>/<subcommand>/`.

## Status

**Read commands shipped:**
`gh version`, `gh api`, `gh repo view/list`,
`gh release list/view/download`, `gh issue list/view`, `gh pr list/view/diff/checks`,
`gh search repos/code/commits/issues/prs`, `gh gist view/list`,
`gh workflow list/view`, `gh run list/view`, `gh label list`,
`gh project list/view/item-list`,
`gh ssh-key list`, `gh gpg-key list`, `gh org list`,
`gh secret list`, `gh variable list/get`, `gh cache list`,
`gh browse`.

**Write commands shipped:**
- API-only:
  - issues: `create / edit / comment / close / reopen / lock / unlock / pin / unpin`
  - PRs: `edit / comment / merge / close / reopen / ready [--undo] / lock / unlock / update-branch`
  - releases: `create / delete`
  - gists: `create / delete`
  - repos: `create / edit / rename / archive / unarchive / delete`
  - workflows: `run (dispatch) / enable / disable`
  - runs: `cancel / rerun [--failed] / delete`
  - keys: `ssh-key add / delete`, `gpg-key add / delete`
  - vars: `variable set / delete`
  - cache: `cache delete`
  - labels: `create / edit / delete`
  - secrets: `delete` (set deferred — needs libsodium SealedBox)
- Git-aware (shell out to `git` via `ProcessGitClient`):
  `gh repo clone / fork [--clone] / create --clone`,
  `gh pr checkout / create`.

**Auth shipped:**
`gh auth login [--web] [--clipboard]` (OAuth device flow → Keychain),
`gh auth logout`, `gh auth status` (GraphQL viewer{} probe with
source disclosure: env vs keychain vs hosts.yml; surfaces token scopes
from X-OAuth-Scopes), `gh auth token`.

**Config shipped:**
`gh config get/set/list` — reads/writes `~/.config/gh/config.yml`
in upstream-gh's exact YAML format (interoperable: edits made by Go
gh are read by SwiftGH and vice versa).

**Foundation shipped:**
- `ConfigurationResolver` with precedence
  `GH_TOKEN > GITHUB_TOKEN > SecretStore[host] > hosts.yml.oauth_token`.
- `ConfigFile` + `HostsFile` (Yams-backed read+write,
  upstream-gh-format-compatible). 0o600 file perms / 0o700 dir perms.
- `GitClient` protocol with reads (`remoteURL`, `currentBranch`,
  `upstreamBranch`) AND writes (`clone`, `fetch`, `checkout`, `push`,
  `addRemote`). `ProcessGitClient` shells out to `git` so the user's
  ssh-agent / credential helpers / commit signing / hooks all apply.
  `NoGitClient` throws `GitClientError.gitUnavailable` from writes
  for sandboxed embedders. Used by `RepositoryResolver` so every
  `--repo`-taking command becomes optional.
- `APIClient.send<Body, Response>` / `delete` for typed write paths.
- `GraphQLClient` actor with envelope decoding + aggregate-error throwing.
- `OAuthDeviceFlow` actor (full RFC 8628 flow with all terminal error
  states mapped; mocked test covers multi-attempt poll loop).
- `SecretStore` protocol; `KeychainSecretStore` (Apple), `InMemorySecretStore`.
- `MinimalRepository` for trimmed list/search payloads.
- `TTY` + `ANSI` helpers (NO_COLOR / CLICOLOR_FORCE honored).
- `ProjectQueries` — canonical GraphQL queries as named constants;
  `ProjectV2` + `ProjectV2Item` (polymorphic content via `__typename`).

**Adopted (Apple/swiftlang/community):** `swift-argument-parser`,
`swift-log`, `swift-http-types`, `swift-configuration` (+ YAML /
CommandLineArguments traits), `swift-crypto`, `Yams` (YAML write
side), `Security` framework.

**Next, in roughly priority order:**
1. **More REST coverage.** secret / variable / ssh-key / gpg-key /
   ruleset / cache / `gh repo delete` (needs the `delete_repo` OAuth
   scope, omitted by default to mirror upstream gh).
2. **GraphQL writes.** `gh project field-list/item-add/item-edit/item-archive/item-delete`,
   `gh issue develop`. Same client; just queries + mutations.
3. **`gh pr edit/review/diff/checks`** — straightforward once we have
   review-comment + check-run models.
4. **`gh release upload`** + `gh release delete-asset` — multipart uploads.
5. **`gh issue/pr edit`** — PATCH-back the title/body/labels/etc.
6. **`gh browse`** — open URL in default browser
   (NSWorkspace / xdg-open / start).
7. **TUI / interactive wizards** — lowest priority; non-interactive
   flags cover the same ground.

**Skipped indefinitely:** `gh attestation` (Sigstore stack),
`gh codespace ssh` (dev-tunnels + PTY), `gh extension install`
(Go-binary plugin model), web-OAuth flow (browser + localhost
listener; device flow is sufficient).

## Build & test

```bash
swift build
swift test                                 # full suite (Swift Testing)
swift test --filter SwiftGHCoreTests       # one target
swift run gh <subcommand> ...              # run the CLI from source
```

A `release` build produces `.build/release/gh`.

## Layout

```
Sources/
  SwiftGHCore/        Pure types: clients, models, decoders. No
                      ArgumentParser, no I/O policy. Embeddable.
    Networking/       APIClient (get/paginate/raw/send/delete),
                      APIError, Pagination, APIResponse
    GraphQL/          GraphQLClient, GraphQLRequest, GraphQLResponse,
                      GraphQLValue, GraphQLError, ViewerQuery
    Auth/             OAuthDeviceFlow, DeviceCode, AccessToken,
                      OAuthDeviceFlowError
    Secrets/          SecretStore, InMemorySecretStore,
                      KeychainSecretStore, DefaultSecretStore
    Git/              GitClient, ProcessGitClient, NoGitClient,
                      RepositoryReference+RemoteURL
    Configuration/    Configuration (ConfigReader-backed),
                      ConfigurationResolver, TokenSource
    IO/               TTY (isatty + NO_COLOR/CLICOLOR_FORCE),
                      ANSI (inert when colour disabled)
    Decoding/         JSONDecoder factory + custom strategies
    Models/           One Codable struct per file. Enums for
                      string-with-fixed-values fields.
    Models/Requests/  Encodable structs for write payloads
                      (IssueCreate, IssueComment, IssueStateUpdate,
                       ReleaseCreate, GistCreate, …)
                      string-with-fixed-values fields.
    Logging/          swift-log Logger constants
  SwiftGHCommand/     Argument-Parser layer.
    GhCommand.swift   Root.
    Subcommands/<group>/<leaf>.swift  — one file per leaf command.
  gh/                 Executable target. ~10 lines, calls
                      GhCommand.main().
Tests/
  SwiftGHCoreTests/
    Fixtures/         JSON captures from real API responses.
    *Tests.swift      Decode tests, pagination tests, URL building.
  SwiftGHCommandTests/
    *Tests.swift      Subcommand integration tests with mocked APIClient.
```

**One declaration per file.** Big types split via
`Type+Concern.swift` extensions. Protocol conformances split into
`Type+Protocol.swift` (e.g. `Repository+CustomStringConvertible.swift`)
when they're more than a few lines.

## Codable strategy

Every API decoder is created via `JSONDecoder.gitHub()`:

```swift
extension JSONDecoder {
    static func gitHub() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601           // RFC 3339 with Z
        d.dataDecodingStrategy = .base64            // file-contents API
        return d
    }
}
```

**Models should not declare `CodingKeys` or custom `init(from:)`.**
The decoder strategy maps `pushed_at` → `pushedAt`, `html_url` →
`htmlUrl`, etc. automatically. If a property name collides with a
Swift keyword, rename via a thin computed property rather than custom
keys (`var defaultBranch: String` mapped from `default_branch` works
fine).

Exceptions where custom code *is* OK:
- A field that's polymorphic / type-tagged (e.g. event payloads).
- A field that's a date in a non-ISO8601 format (rare; commit dates
  in some endpoints).

When you must, put the custom decode in `Model+Codable.swift`.

## Argument-Parser conventions

- One leaf command = one `struct: AsyncParsableCommand`.
- Group commands (e.g. `Repo`, `Pr`) are also `AsyncParsableCommand`s
  with `subcommands:` listing leaves and a no-op `run()`.
- Use `@Argument`, `@Option`, `@Flag`. No manual argv parsing.
- Help text uses Swift multi-line strings, not `heredoc.Doc` (Go).
  Mirror gh's wording where reasonable.
- Long descriptions belong in `discussion:`; one-liners in `abstract:`.

## Logging

`swift-log`. Each subsystem owns one logger:

```swift
enum Loggers {
    static let api = Logger(label: "com.swiftgh.api")
    static let auth = Logger(label: "com.swiftgh.auth")
    static let cmd = Logger(label: "com.swiftgh.cmd")
}
```

Levels: `.debug` for request URL/method/headers, `.info` for high-level
flow, `.warning` for retried failures, `.error` for fatal-to-the-command.
Default backend is the stdlib stream handler; embedders can swap.

## Testing conventions

- **Swift Testing** (`@Test`, `#expect`, `#require`), not XCTest.
- Decode tests load JSON from `Tests/SwiftGHCoreTests/Fixtures/` and
  `#expect` field equality. One fixture per real API call captured.
- HTTP mocking via a `URLProtocol` subclass (no Mockingbird etc.).
  `APIClient` accepts an injected `URLSession` so tests use a session
  configured with the mock protocol.
- Live tests are tagged `.live` and gated on `SWIFTGH_LIVE=1`. They
  hit `api.github.com` (unauthenticated for REST against
  `octocat/Hello-World` + `cli/cli`; with `GH_TOKEN` for the GraphQL
  viewer{} probe).
- Real-Keychain integration tests are gated on
  `SWIFTGH_KEYCHAIN_TESTS=1` to keep CI off the user's login keychain.
- Suites that share `MockURLProtocol.handler` (a process global) live
  inside one `@Suite(.serialized)` parent
  (`HTTPMockedNetworkTests`). Swift Testing only serializes within a
  suite hierarchy, so adding a new mocked-HTTP suite means nesting it
  under that parent.

## Adopted Apple/swiftlang packages

- **swift-argument-parser** — every `*Command`.
- **swift-log** — `Loggers.api`, `.auth`, `.cmd`.
- **swift-http-types** + `HTTPTypesFoundation` — `HTTPRequest` /
  `HTTPResponse` flow through `APIClient` + `GraphQLClient` +
  `OAuthDeviceFlow`. URLSession is the transport.
- **swift-configuration** (with `YAML` and `CommandLineArguments` traits)
  — `Configuration.live()` reads via `ConfigReader +
  EnvironmentVariablesProvider`. Ready to layer in
  `~/.config/gh/config.yml` (just add a `FileProvider<YAMLSnapshot>`
  to the chain).
- **swift-crypto** — pulled in for the upcoming PKCE story (currently
  unused; placeholder dep).
- **Security** (Apple-system) — `KeychainSecretStore`.

## Investigated, not adopted

- **swift-openapi-generator** + `github/rest-api-description` — would
  auto-generate every model and endpoint method from GitHub's
  ~9 MB official OpenAPI spec. Force multiplier for a feature-complete
  port. Tradeoffs: 9 MB spec checked in, generated-code mass, generated
  CodingKeys diverge from our `convertFromSnakeCase` Codable
  convention. Defer until we hit the long tail of write commands; until
  then the hand-rolled Codable structs are a better fit.
- **Apollo iOS** — too heavy for our needs. GraphQL surface here is
  small (single endpoint, opaque queries); a hand-rolled
  `GraphQLClient` is ~80 LOC and shares the `JSONDecoder.gitHub()`
  convention.

## Third-party Go deps and their Swift stories

The Go `gh` binary's transitive dep tree (see
`~/Developer/Others/cli/go.mod`) is large. Many deps map cleanly to
Foundation; some need Swift ports of their own. This list is the
porting roadmap.

| Go dep | Role | Swift story |
|---|---|---|
| `cli/go-gh` | gh's foundational lib (api client, config, auth, browser) | Portions of this are now `SwiftGHCore` (api client, configuration, networking). |
| `cli/oauth` | OAuth web + device flow | **Done** for the device flow (`SwiftGHCore/Auth/`). Web flow deferred. |
| `cli/safeexec` | Lookup external bins | Foundation `Process` (used by `ProcessGitClient`). No standalone port needed. |
| `cli/browser` | Open URL in default browser | `NSWorkspace.shared.open` (Mac) / `UIApplication.shared.open` (iOS) / `xdg-open` (Linux). Will land with `gh browse`. |
| `cli/shurcooL-graphql` | GraphQL client | **Done** — hand-rolled `GraphQLClient` in `SwiftGHCore/GraphQL/` (~150 LOC). |
| `zalando/go-keyring` | Credential storage | **Done** for Apple platforms (`KeychainSecretStore`). Linux libsecret backend TBD. |
| `MakeNowJust/heredoc` | Strip leading indent | Swift multi-line strings handle this natively. No port. |
| `kballard/go-shellquote` | Shell quote/unquote | ~50 LOC port; trivial. |
| `mgutz/ansi` | ANSI colour codes | Port or use `swift-rainbow` / hand-roll. |
| `mattn/go-isatty` | TTY detection | `isatty(fileno(stdout))` — 1 line via Darwin/Glibc. |
| `mattn/go-colorable` | Windows ANSI shim | Skip until Windows support is in scope. |
| `briandowns/spinner` | Terminal spinner | Hand-roll — ~100 LOC. |
| `charmbracelet/glamour` | Markdown → terminal renderer | Port is huge. Defer; print raw markdown until then. |
| `charmbracelet/bubbletea` family | TUI | Skip. SwiftUI-on-CLI doesn't exist. Replace with non-interactive flags. |
| `charmbracelet/lipgloss` | Terminal styling | Skip with bubbletea. |
| `rivo/tview` | TUI (gh codespace ssh chrome) | Skip. |
| `henvic/httpretty` | Pretty HTTP debug logging | swift-log + a custom `URLProtocol` middleware. |
| `joho/godotenv` | `.env` loader | ~30 LOC port. |
| `gabriel-vasile/mimetype` | MIME from magic bytes | `UniformTypeIdentifiers` (Apple); pure-Swift table for Linux. |
| `AlecAivazis/survey/v2` | Interactive prompts | Hand-roll a `Prompter` protocol with readline-based default impl. |
| `atotto/clipboard` | Read/write OS clipboard | `NSPasteboard` / `UIPasteboard` / `xclip`/`wl-copy`. |
| `hashicorp/go-version` | Semver parse + compare | Port: `SwiftSemver`. ~200 LOC. |
| `microsoft/dev-tunnels` | Codespaces port-forwarding | Defer with `gh codespace ssh`. Big subsystem. |
| `google/go-containerregistry` | OCI registry client | Defer with `gh attestation`. |
| `sigstore/sigstore-go`, `sigstore/protobuf-specs`, `theupdateframework/go-tuf/v2`, `digitorus/timestamp`, `in-toto/attestation` | Sigstore attestation verification | Defer with `gh attestation`. Massive scope. |
| `cenkalti/backoff` | Exponential backoff | ~50 LOC port; or hand-roll inline. |
| `vmihailenco/msgpack/v5` | MessagePack codec | Defer (only used by send-telemetry). |
| `klauspost/compress` | gzip/zstd | Foundation has gzip via `compression_*`; zstd needs a C dep. |
| `cli/browser`, `cli/oauth`, `cli/safeexec`, `cli/shurcooL-graphql` | small cli/* helpers | Bundle into `SwiftGHCore`. |
| `gorilla/websocket` | WebSocket | `URLSessionWebSocketTask` (built-in). |
| `creack/pty` | PTY | Defer with codespace SSH. |
| `gdamore/tcell/v2`, `rivo/tview` | Terminal cell rendering | Skip with TUI. |
| `cpuguy83/go-md2man` | Markdown → man-page | Only used by `gen-docs`, the doc generator. Skip until man-page generation matters. |
| `yuin/goldmark` | Markdown parser | Used by glamour. Defer. |
| `google/uuid` | UUIDs | `Foundation.UUID`. |
| `google/go-cmp` | Test diffing | Swift Testing's diff is fine. |
| `gopkg.in/yaml.v3` | YAML | **swift-configuration** for reads (with `YAML` trait); `Yams` will be added when write paths land (`gh config set`, `gh auth login`). |
| `MichaeMakeNowJust/heredoc`, `Masterminds/sprig`, `Masterminds/semver` | template helpers | Avoid; use Swift string interpolation. |

The library list above is the ground truth for "what would need to
exist in Swift for a 100% port." Most of these are skip-able for the
no-auth surface; revisit each as the corresponding subcommand comes up.

## What we deliberately do NOT support (yet)

- **Web OAuth flow** — needs to spawn a browser and listen on
  localhost. Hostile to embedded use; deferred indefinitely. The
  device flow (already implemented in `Auth/OAuthDeviceFlow.swift`)
  is the path forward.
- **Glamour markdown rendering** — print raw markdown for now.
- **TUI / interactive wizards** — pass `--title`, `--body`, `--head`,
  etc. instead.
- **`gh attestation`** — enormous Sigstore stack. Defer.
- **`gh codespace ssh`** — needs Microsoft dev-tunnels + PTY. Defer.
- **`gh extension install`** — gh extensions are external Go binaries;
  the model needs rethinking for a Swift host.

## OAuth client ID

`OAuthDeviceFlow.ghCLIClientID` is the same `client_id` Go gh
embeds (`178c6fc778ccc68e1d6a`). It works for development; **before
SwiftGH ships publicly we must register our own OAuth app** and use
that ID as the default. Reusing gh's identity attributes SwiftGH
usage to the upstream gh project, which is incorrect.

Step-by-step setup, including the exact form fields and post-registration
wiring: [Docs/OAuthAppSetup.md](Docs/OAuthAppSetup.md).

## Gotchas

- GitHub returns `null` for many optional fields. Make properties
  `Optional`, not non-optional with a default. The decoder will
  populate `nil` correctly; defaults silently swallow real `null`s.
- Pagination uses RFC 5988 `Link` headers. `APIClient.paginate(...)`
  walks `rel="next"` until exhausted. Don't roll your own per-command.
- `gh api` paths can be REST (`repos/cli/cli`) or GraphQL (`graphql`).
  The Go `gh api` auto-detects; we should match.
- The default API hostname is `api.github.com`, but `GH_HOST` /
  `--hostname enterprise.example.com` rewrites it to
  `enterprise.example.com/api/v3`. Path construction goes through
  `Configuration.apiURL(for:)`.
- Rate-limit headers (`X-RateLimit-Remaining`, `X-RateLimit-Reset`)
  are logged at `.debug`; if `Remaining == 0`, surface a clear error
  pointing at the reset time and the unauth → auth token recipe.

## Adding a new subcommand

1. Add the model(s) under `Sources/SwiftGHCore/Models/` if not present.
2. Add an APIClient method or use the generic `get`/`paginate`.
3. Capture a real response: `curl -s -H 'Accept: application/vnd.github+json' https://api.github.com/...` → save to `Tests/SwiftGHCoreTests/Fixtures/`.
4. Write a decode test consuming the fixture.
5. Add the leaf command file under
   `Sources/SwiftGHCommand/Subcommands/<group>/<leaf>.swift`.
6. Register in the parent group's `subcommands:`.
7. Run `swift test` and `swift run gh <new command> --help` to verify.

## Conventions to keep

- Plain English in user-facing strings; mirror gh's wording when in
  doubt.
- Exit codes mirror gh: `0` success, `1` generic failure, `2` usage
  error (Argument-Parser does this), `4` HTTP not-found.
- Errors thrown from `run()` get printed by Argument-Parser. Use
  `ExitCode` and a custom `Error` type with `LocalizedError`
  conformance for clean messages.
- Keep `SwiftGHCore` Foundation-only — no Argument-Parser dep — so it
  stays usable from non-CLI hosts.
