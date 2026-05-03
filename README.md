# SwiftPorts

Pure-Swift, cross-platform reimplementations of the CLI utilities you
reach for when working with source repositories — so you can **embed
them in apps instead of shelling out**.

## Mission

To have pure-Swift implementations of CLI utilities used for working
with repos, so they can be embedded in apps and remove the need to
shell out to run them. To support the most-used commands with
identical functionality, output, and error cases. To build on
[`ArgumentParser`](https://github.com/apple/swift-argument-parser) so
the same Command structs can be registered as
[SwiftBash](https://github.com/Cocoanetics/SwiftBash) builtins —
once we've figured out how to implement sandbox behaviour and / or a
virtual in-memory filesystem.

## Why these tools, in this order

The current port set is `zip`, `unzip`, `gh`, `glab`, and `git`.
That's not a random list — they're **chained dependencies of the
"work with a repo" workflow**:

```
git ──┐
      ├── ports the local-side operations (clone, fetch, checkout,
      │   add, commit, push, …) without shelling out to /usr/bin/git
      │
gh ───┤── reads/writes GitHub remotes (issues, PRs, releases,
      │   workflows, …); calls into git for clone / pr checkout /
      │   pr create
      │
glab ─┤── same role for GitLab (issues, MRs, pipelines, …);
      │   shares the host-agnostic CLI plumbing (IO, Git, Secrets)
      │   with gh via ForgeKit
      │
zip ──┤── creates `.zip` archives — used by gh's
      │   `gh run download / view --log` to handle the ZIPs the
      │   Actions API hands back
      │
unzip ─    extracts them
```

Each one closes a hole the others would otherwise have to leave to
the system. With all five, an iOS / sandboxed macOS / server-side
Swift app can do everything from cloning a repo, opening an issue,
inspecting a CI pipeline, downloading a workflow artifact, and
unpacking it — without ever running `Process`.

## What ships today

| Library        | Binary | What it ports |
|----------------|--------|----------------|
| `ForgeKit`     | —      | Host-agnostic CLI plumbing: ANSI/TTY, GitClient (Process + No-op), SecretStore (Keychain + InMemory). Shared by `gh` and `glab`. |
| `ZipKit`       | —      | PKZIP archive operations on top of [`weichsel/ZIPFoundation`](https://github.com/weichsel/ZIPFoundation). Shared by `zip` / `unzip` / `gh`. |
| `ZipCommand`   | `zip`  | Info-ZIP `zip(1)` — create archives. |
| `UnzipCommand` | `unzip`| Info-ZIP `unzip(1)` — extract / list / test / pipe. |
| `GitHub`       | —      | GitHub SDK: REST + GraphQL clients, OAuth device flow, Codable models. No ArgumentParser dep. |
| `GhCommand`    | `gh`   | The `gh` subcommand tree. |
| `GitLab`       | —      | GitLab SDK: REST client (`X-Next-Page` pagination, Bearer auth, `gitlab.com` and self-hosted), Codable models, nested-subgroup-aware `RepositoryReference`. |
| `GlabCommand`  | `glab` | The `glab` subcommand tree. |
| `SwiftGit`     | —      | In-process `GitClient` impl backed by libgit2 1.9.x. Drop-in replacement for `ForgeKit`'s `ProcessGitClient` — no system `git` binary required. |
| `GitCommand`   | `git`  | A `git` CLI built on `SwiftGit`. SwiftBash can register `GitCommand` as the `git` builtin to shadow the system binary. |

### Surface coverage

- **`gh`** — close to the upstream surface. `auth login --web` runs
  the OAuth device flow; full subcommand surface across `repo`, `pr`,
  `issue`, `release`, `workflow`, `run`, `gist`, `project`, `label`,
  `org`, `cache`, `variable`, `secret`, `ssh-key`, `gpg-key`, `search`,
  `config`. See [Docs/GitHub.md](Docs/GitHub.md) for status detail.
- **`glab`** — `issue` (full surface incl. board management),
  `mr` (full surface incl. checkout / diff / approve / merge),
  `ci` (list / view / trace / status / retry / cancel / run),
  `repo` (view / list / create / clone / fork / archive / unarchive /
  delete), `auth` (status / login PAT-based / logout / token).
  See [Docs/GitLab.md](Docs/GitLab.md).
- **`git`** — clone / fetch / checkout / push / add / commit /
  remote / branch / version. Backed by libgit2 in-process; HTTPS
  auth via a `CredentialProvider` callback.
- **`zip` / `unzip`** — the most-used Info-ZIP flag set, no shellout.

## Quick start

```bash
swift build                                # builds everything
swift test                                 # all targets, all tests
swift run gh   issue list -R cli/cli       # GitHub CLI
swift run glab issue list -R group/repo    # GitLab CLI
swift run git  clone https://…             # libgit2-backed git
swift run zip  out.zip src/                # zip(1)
swift run unzip out.zip                    # unzip(1)
```

`swift build -c release` produces optimized binaries under
`.build/release/`. Drop them on your `$PATH` and the macOS Keychain
"Always Allow" button persists across runs of that exact binary.

## Embedding in your app

The SDK libraries (`GitHub`, `GitLab`, `ZipKit`, `SwiftGit`,
`ForgeKit`) have **zero `ArgumentParser` dependency** — they're
plain Swift APIs. Use them directly when you don't need a CLI:

```swift
import GitLab
import ForgeKit

let client = APIClient(configuration:
    Configuration(host: "gitlab.com",
                  token: ProcessInfo.processInfo.environment["GITLAB_TOKEN"]))
let issues: [Issue] = try await client.get(
    "projects/group%2Frepo/issues",
    query: [URLQueryItem(name: "state", value: "opened")])
```

The Command libraries (`GhCommand`, `GlabCommand`, `GitCommand`,
`ZipCommand`, `UnzipCommand`) expose the AsyncParsableCommand types
as a library product — so SwiftBash extends them in one line:

```swift
import GlabCommand
import BashInterpreter
extension GlabCommand: ParsableBashCommand { … }
```

Registering one of these makes the entire subcommand tree
(`glab issue list`, `glab mr view`, `glab ci trace`, …) addressable
as a single Bash builtin.

## Project layout

Every port that ships both a library and a binary lives under an
umbrella folder:

```
Sources/<Umbrella>/Lib/             ← SDK library, no ArgumentParser
Sources/<Umbrella>/<X>Command/      ← AsyncParsableCommand types
Sources/<Umbrella>/<x>/             ← @main wrapper (one file)
```

So the dependency direction is one-way: `<x>` exec → `<X>Command`
lib → `<Umbrella>` SDK lib → `ForgeKit`. Pure libraries (`ForgeKit`)
sit flat at `Sources/<Name>/`.

For the conventions in detail — naming, target boundaries, how to
add a new port, how SwiftBash integrates — see [AGENTS.md](AGENTS.md).
For per-port status / inventory: [Docs/GitHub.md](Docs/GitHub.md),
[Docs/GitLab.md](Docs/GitLab.md).

## License

MIT. See [LICENSE](LICENSE).
