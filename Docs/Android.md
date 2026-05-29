# Android support

SwiftPorts cross-compiles its **SDK libraries** for Android and **runs
their test suites** on an x86_64 emulator, via
[`skiptools/swift-android-action@v2`](https://github.com/skiptools/swift-android-action)
(Swift 6.3.2, NDK targeting API 28+). The latest `build-android` run
executes **283 tests across 43 suites** on-device.

The realistic Android consumer is
[SwiftBash](https://github.com/Cocoanetics/SwiftBash) embedding the SDK
libraries, so the SDK layer is what's covered here. The ArgumentParser
command/executable layer is excluded on Android (see below); it isn't a
real Android use case.

## What runs on Android

Every **SDK library** compiles, links, and has its test suite run on the
emulator: `ForgeKit`, `ZipKit`, `TarKit`, `GzipKit` (zlib), `JqKit`,
`GlamKit`, `GitLab`, `SwiftGit` (libgit2), `RipgrepKit`, `FdKit`,
`SQLiteKit` (vendored SQLite) — plus the C shims and the vendored
libgit2 / SQLite / libarchive.

Excluded from the Android build (with reasons below):

| Excluded | Why |
|---|---|
| `*Command` libs, executables, argv-parsing test targets | ArgumentParser scanner cycle (§1) |
| `GitHubTests` | links a C++ target (BoringSSL) → C++ link driver (§2) |
| `Bzip2Kit`/`XzKit`/`ZstdKit`/`Lz4Kit` tests | NDK lacks bz2/lzma/zstd/lz4 (source-gated already) |
| `SwiftGit` `Process`-fixtured integration tests | no `git` binary on the emulator (source-gated already) |

## §1 — ArgumentParser explicit-module scanner cycle

Building the full `--build-tests` graph on Android trips a **spurious**
explicit-module-scanner diagnostic:

```
error: circular dependency between modules 'Android' and 'ArgumentParser'
```

It's a false positive (`-Rmodule-loading` shows nothing in the `Android`
overlay's closure actually depends on `ArgumentParser`); the graph just
has many modules importing the `Android` libc overlay, and at this scale
the scanner mis-detects a cycle. It fires nondeterministically on the
`*Command` libraries or test targets, so per-target gating can't fix it.
SwiftBash's smaller graph never trips it on the same toolchain.

**Mitigation (two parts):**

1. **Keep ArgumentParser off every SDK library's module graph** — it
   used to arrive transitively through two always-imported base libs:
   - `ShellKit` — its `ParsableCommandBridge` (`Shell.register(_:)`) was
     split into a separate `ShellCommandKit` product, so core `ShellKit`
     has zero ArgumentParser dependency.
   - `ForgeKit` — `ColorChoice` dropped `import ArgumentParser` /
     `ExpressibleByArgument`; it's a plain value type now (keeps
     `init?(argument:)` for the hand-rolled `rg`/`fd` parsers), and the
     conformance is declared in `GitCommand` (the only `@Option` user).

   This restores the AGENTS.md invariant that SDK libs carry no
   ArgumentParser dependency.

2. **Drop the ArgumentParser command/executable layer for Android.**
   The action sets `TARGET_OS_ANDROID=1`, which `Package.swift` reads via
   `Context.environment` to exclude the `*Command` libs, executables, and
   argv-parsing test targets (`androidDroppedTargets`, 94 → 37 targets).

## §2 — keeping the xctest executable's link clean

With §1 done, the SDK layer compiles, but linking
`SwiftPortsPackageTests.xctest` originally failed with undefined Bionic
libc symbols (`__libc_init` / `__errno` / `__assert2` / `__sF`). Two
distinct host-toolchain leaks had to be removed:

- **Host C++ stdlib.** A C++ SwiftPM target in the bundle routes the link
  through clang's C++ driver, which injects host C++ defaults
  (`-lstdc++` + a host `/usr/lib/x86_64-linux-gnu` search path) that pull
  host glibc. Only `GitHubTests` reaches a C++ target (swift-crypto's
  BoringSSL), so it's in `androidDroppedTargets`. (GitHubTests still runs
  on the four full-build platforms.)

- **Host pkg-config.** `CZlib` used `pkgConfig: "zlib"`; on a cross-build
  SwiftPM runs **host** pkg-config, injecting `-L/usr/lib/x86_64-linux-gnu
  -lz`, so the host libz again pulls host glibc. `pkgConfig` is removed —
  the modulemap's `link "z"` still links zlib (against the sysroot on
  Android; default/CI include paths elsewhere).

- **`-lpthread`.** Android's Bionic merges pthread into libc (no separate
  `libpthread.so`), so `SQLiteKit`'s `linkedLibrary("pthread")` is gated
  to Linux only. (`libm`/`libdl` are real `.so` in the NDK and stay.)

With those gone, `-lz`/libc resolve against the sysroot and the xctest
executable links + runs.

## Source-level fixes for Android

- **`isatty`** — [`Sources/ForgeKit/IO/TTY.swift`](../Sources/ForgeKit/IO/TTY.swift)
  imports the platform libc (`Darwin`/`Glibc`/`Musl`/`Android`). The
  Swift Android SDK exposes libc as the `Android` module (Bionic is a
  subset of it, so no `Bionic` fallback).
- **`stat`/`lstat`/`S_IFMT`/`S_IFIFO`** — the same shim in
  [`Sources/FdKit/Lib/Filter/EntryFilter.swift`](../Sources/FdKit/Lib/Filter/EntryFilter.swift)
  (Foundation re-exports them on Darwin/Linux but not under the Android SDK).
- **`GIT_REBASE_NO_OPERATION`** — libgit2's `#define … SIZE_MAX` isn't
  surfaced by the Android importer;
  [`GitClient+Rebase.swift`](../Sources/SwiftGit/Lib/GitClient+Rebase.swift)
  compares in `size_t` space (also fixes a latent overflow on every platform).

## Downstream note: SwiftBash

`Shell.register(_:)` / the `ParsableCommand` bridge moved from `ShellKit`
into the new `ShellCommandKit` product. SwiftBash registers SwiftPorts
command trees as Bash builtins, so it needs to add `ShellCommandKit` to
the relevant target's dependencies and `import ShellCommandKit` where it
calls `register`.

## CI workflow

`.github/workflows/swift.yml` → `build-android`:

- `skiptools/swift-android-action@v2`, `swift-version: "6.3.2"` (a full
  patch pin — floating `6.3` drifts the host toolchain ahead of the SDK).
- `free-disk-space: true` — SDK + NDK + emulator overrun the runner's
  ~14 GiB.
- `build-tests` / `run-tests` default on — the SDK suites run on the
  emulator.

## Adding a new target

Add it in `Package.swift` as usual.

- ArgumentParser command/executable layer (a `*Command` lib, executable,
  or argv-parsing test) → add its name to `androidDroppedTargets`.
- A test target that links a **C++** SwiftPM target → also add it to
  `androidDroppedTargets` (else the C++ link driver re-pollutes the link).
- Uses a libc symbol directly → add the `canImport(Android)` import shim.
- Depends on a system C library the NDK lacks (bz2/lzma/zstd/lz4), or on
  `pthread` → gate that dependency to `[.macOS, .linux, .windows]` (or
  `[.linux]` for pthread), and avoid `pkgConfig:` on system libraries
  needed by the Android build (host pkg-config pollutes the cross-link).
