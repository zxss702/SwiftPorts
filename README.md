# SwiftPorts

![SwiftPorts](Docs/SwiftPorts.jpg)

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

The current port set is `git`, `gh`, `glab`, the archive family
(`zip` / `unzip` / `tar`), the compression family (`gzip` / `bzip2` /
`xz` / `zstd` / `lz4`), and `jq`. That's not a random list — they're
**chained dependencies of the "work with a repo" workflow**:

```
git ──┐
      ├── ports the local-side operations (clone, fetch, checkout,
      │   add, commit, push, …) without shelling out to /usr/bin/git
      │
gh ───┤── reads/writes GitHub remotes (issues, PRs, releases,
      │   workflows, …); calls into git for clone / pr checkout /
      │   pr create; uses jq for `gh api --jq` and the archive +
      │   compression family for `gh release download` (auto-extracts
      │   .zip / .tar / .tar.gz / .tar.bz2 / .tar.xz / .tar.zst /
      │   .tar.lz4) and `gh run download / view --log` (workflow
      │   artifact ZIPs)
      │
glab ─┤── same role for GitLab (issues, MRs, pipelines, …);
      │   shares the host-agnostic CLI plumbing (IO, Git, Secrets)
      │   with gh via ForgeKit; same `glab api --jq` integration
      │
zip / unzip / tar ──┐
                    ├── archive operations — referenced by gh / glab
                    │   for release assets and workflow artifacts
gzip / bzip2 / xz / zstd / lz4 ──┐
                                 ├── stream codecs that back the
                                 │   tar.* chain on every supported
                                 │   platform
jq ──┘── in-process JSON filtering for `gh api --jq` / `glab api --jq`
```

Each one closes a hole the others would otherwise have to leave to
the system. Together, an iOS / sandboxed macOS / server-side Swift
app can clone a repo, open an issue, inspect a CI pipeline, download
and unpack a release tarball, and filter the response with jq —
without ever running `Process`.

## What ships today

| Library         | Binary                       | What it ports |
|-----------------|------------------------------|----------------|
| `ForgeKit`      | —                            | Host-agnostic CLI plumbing: ANSI/TTY, GitClient (Process + No-op), SecretStore (Keychain + InMemory). Shared by `gh` and `glab`. |
| `ZipKit`        | —                            | PKZIP archive operations on top of [`weichsel/ZIPFoundation`](https://github.com/weichsel/ZIPFoundation). Shared by `zip` / `unzip` / `gh`. |
| `ZipCommand`    | `zip`                        | Info-ZIP `zip(1)` — create archives. |
| `UnzipCommand`  | `unzip`                      | Info-ZIP `unzip(1)` — extract / list / test / pipe. |
| `TarKit`        | —                            | POSIX tar with libarchive backend; auto-detects gzip / bzip2 / xz / zstd / lz4 filters. |
| `TarCommand`    | `tar`                        | `tar(1)` — `-c` / `-x` / `-t` with the standard flag set. |
| `GzipKit`       | —                            | Single-file gzip via zlib; works everywhere zlib does. |
| `GzipCommand`   | `gzip` / `gunzip` / `zcat`   | The three gzip personalities. |
| `Bzip2Kit`      | —                            | Single-file bzip2 via libbz2's stream API (macOS / Linux / Windows). |
| `Bzip2Command`  | `bzip2` / `bunzip2` / `bzcat`| The three bzip2 personalities. |
| `XzKit`         | —                            | Single-file xz / lzma2. Apple platforms back it with `Compression.framework`'s LZMA path so iOS / tvOS / watchOS / visionOS get real `.xz` support; Linux / Windows use system liblzma. |
| `XzCommand`     | `xz` / `unxz` / `xzcat`      | The three xz personalities. |
| `ZstdKit`       | —                            | Single-file Zstandard via libzstd's stream API (macOS / Linux / Windows). |
| `ZstdCommand`   | `zstd` / `unzstd` / `zstdcat`| The three zstd personalities. |
| `Lz4Kit`        | —                            | Single-file LZ4 frame format. Apple platforms use `Compression.framework`'s `LZ4_RAW` block coder; Linux / Windows use system liblz4. |
| `Lz4Command`    | `lz4` / `unlz4` / `lz4cat`   | The three lz4 personalities. |
| `JqKit`         | —                            | Pure-Swift jq engine (parser + evaluator + builtins) — no system C dep, runs on every supported platform. Public `Jq.eval` / `Jq.evalString` facade. |
| `JqCommand`     | `jq`                         | `jq(1)` — the standard flag set (`-r` / `-c` / `-s` / `-e` / `--arg` / `--argjson` / `--slurpfile` / …). |
| `GitHub`        | —                            | GitHub SDK: REST + GraphQL clients, OAuth device flow, Codable models. No ArgumentParser dep. |
| `GhCommand`     | `gh`                         | The `gh` subcommand tree. `gh api` supports `--jq <filter>` (in-process via JqKit) and the GraphQL `{query, variables, operationName}` envelope. |
| `GitLab`        | —                            | GitLab SDK: REST client (`X-Next-Page` pagination, Bearer auth, `gitlab.com` and self-hosted), Codable models, nested-subgroup-aware `RepositoryReference`. |
| `GlabCommand`   | `glab`                       | The `glab` subcommand tree. `glab api` supports `--jq <filter>` (same JqKit integration). |
| `SwiftGit`      | —                            | In-process `GitClient` impl backed by libgit2 1.9.x. Drop-in replacement for `ForgeKit`'s `ProcessGitClient` — no system `git` binary required. |
| `GitCommand`    | `git`                        | A `git` CLI built on `SwiftGit`. SwiftBash can register `GitCommand` as the `git` builtin to shadow the system binary. |
| `RipgrepKit`    | —                            | Pure-Swift port of BurntSushi/ripgrep — recursive code search with a gitignore-aware `Walker`, an `NSRegularExpression`-backed `PatternMatcher`, and JSON-Lines output compatible with rg `--json` consumers. |
| `RgCommand`     | `rg`                         | `ripgrep(1)` — `-i/-S/-s`, `-F`, `-w`, `-x`, `-v`, `-U`, `-A/-B/-C`, `-t/-T`, `-g/--iglob`, `--hidden`, `--max-depth`, `--no-ignore` family, `-c`, `-l`, `--files`, `--json`, `--vimgrep`, …. |
| `FdKit`         | —                            | Pure-Swift port of sharkdp/fd — file/directory finder. Reuses `RipgrepKit`'s `Walker` (with `.fdignore` swapped in for `.rgignore`) and layers a tri-syntax pattern matcher (regex / glob / fixed-string), `--type` / `--size` / `--changed-*` / `--exclude` filters, and an LS-style printer. |
| `FdCommand`     | `fd`                         | `fd(1)` — `--glob`/`--regex`/`-F`, `-p/--full-path`, `-e/--extension`, `-t/--type`, `-E/--exclude`, `-S/--size`, depth bounds, `--max-results`/`-1`, `-H/--hidden`, `--no-ignore` family, `-a/--absolute-path`, `-0/--print0`, `--color`, …. |

### Surface coverage

- **`gh`** — close to the upstream surface. `auth login --web` runs
  the OAuth device flow; full subcommand surface across `repo`, `pr`,
  `issue`, `release`, `workflow`, `run`, `gist`, `project`, `label`,
  `org`, `cache`, `variable`, `secret`, `ssh-key`, `gpg-key`, `search`,
  `config`. See [Docs/GitHub.md](Docs/GitHub.md) for status detail.
- **`glab`** — `issue` (full surface incl. board management),
  `mr` (full surface incl. checkout / diff / approve / merge),
  `ci` (list / view / trace / status / retry / cancel / run / lint),
  `repo` (view / list / create / clone / fork / archive / unarchive /
  edit / delete), `release` (list / view / create / delete /
  download), `tag`, `variable`, `label`, `api`, and `auth` (status /
  login PAT-based / logout / token). See
  [Docs/GitLab.md](Docs/GitLab.md).
- **`git`** — full local-side surface: `init / clone / fetch / pull
  {--rebase} / push / status / log / diff / show / commit / merge /
  rebase / cherry-pick / reset / checkout / switch / restore / add /
  rm / mv / clean / stash / tag / branch / remote / config /
  rev-parse / ls-files / ls-tree / cat-file / describe / blame /
  apply / reflog`. Backed by libgit2 in-process; HTTPS auth via a
  `CredentialProvider` callback. Output and exit-code semantics
  mirror real git for every supported case.
- **`zip` / `unzip`** — the most-used Info-ZIP flag set, no shellout.
- **`tar`** — `-c` / `-x` / `-t` with auto-detected compression. Used
  in-process by `gh release download` so `.tar.gz` / `.tar.bz2` /
  `.tar.xz` / `.tar.zst` / `.tar.lz4` assets unpack without a
  subprocess.
- **Compression family** — `gzip`, `bzip2`, `xz`, `zstd`, `lz4`, each
  with its `*-cat` and `un-*` personalities. The same engines back
  `tar.*` extraction in `gh`. Apple-mobile coverage varies by codec
  (`gzip` and `xz` and `lz4` on every platform; `bzip2` and `zstd`
  gated to macOS / Linux / Windows because the underlying C library
  isn't in the iOS SDK or Android NDK).
- **`jq`** — pure-Swift implementation of the standard CLI surface.
  Library form (`JqKit`) is what powers `gh api --jq` and
  `glab api --jq` in-process — sandboxed iOS apps can finally filter
  API responses without spawning anything.
- **`rg`** — ripgrep-compatible recursive search with a gitignore-aware
  walker, regex / fixed-string / smart-case modes, type registry, JSON
  Lines (`--json`), and the daily-driver flag set. Engine is reusable
  via `RipgrepKit`.
- **`fd`** — fd-compatible file finder layered on the same walker.
  Supports regex / glob / fixed-string patterns (basename- or
  full-path-matched), `--type`, `--size`, `--changed-*`, `--exclude`,
  depth bounds, `--max-results`, the `--no-ignore` family, `.fdignore`,
  and the standard output knobs (`-0`, `-a`, `--strip-cwd-prefix`).

## Quick start

```bash
swift build                                # builds everything
swift test                                 # all targets, all tests
swift run gh   issue list -R cli/cli       # GitHub CLI
swift run gh   api repos/cli/cli --jq .full_name   # gh api + jq filter
swift run glab issue list -R group/repo    # GitLab CLI
swift run git  clone https://…             # libgit2-backed git
swift run zip  out.zip src/                # zip(1)
swift run unzip out.zip                    # unzip(1)
swift run tar  -xzf release.tar.gz         # tar with gzip filter
swift run jq   '.items[] | .name' < data.json
swift run rg   'TODO' src/                # ripgrep-compatible search
swift run fd   --glob '*.swift' src/      # fd-compatible file finder
```

`swift build -c release` produces optimized binaries under
`.build/release/`. Drop them on your `$PATH` and the macOS Keychain
"Always Allow" button persists across runs of that exact binary.

## Embedding in your app

The SDK libraries (`GitHub`, `GitLab`, `ZipKit`, `TarKit`, `GzipKit`,
`Bzip2Kit`, `XzKit`, `ZstdKit`, `Lz4Kit`, `JqKit`, `SwiftGit`,
`RipgrepKit`, `FdKit`, `ForgeKit`) have **zero `ArgumentParser` dependency** — they're
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
