# Android support

SwiftPorts compiles its library targets against the Swift Android SDK
(via [`skiptools/swift-android-action@v2`](https://github.com/skiptools/swift-android-action),
Swift 6.3, NDK targeting API 28+). The CI matrix's `build-android` job
reflects exactly what works today.

## What builds on Android

| Target          | Kind     | Status |
|-----------------|----------|--------|
| `ForgeKit`      | library  | ✅ |
| `ZipKit`        | library  | ✅ |
| `ZipCommand`    | library  | ✅ |
| `UnzipCommand`  | library  | ✅ |
| `GitHub`        | library  | ✅ |
| `GhCommand`     | library  | ✅ |
| `GitLab`        | library  | ✅ |
| `GlabCommand`   | library  | ✅ |
| `SwiftGit`      | library  | ✅ |
| `GitCommand`    | library  | ✅ |

Every library target compiles. They're listed explicitly via `--target`
flags in the workflow because the build's link phase trips on a separate
issue (see below).

## What doesn't build on Android

| Target                       | Kind                | Blocker |
|------------------------------|---------------------|---------|
| `zip`, `unzip`, `gh`, `glab`, `git` | executables  | linker `undefined symbol: __libc_init` |
| All `*Tests` test bundles    | test executables    | same link path |

## Required fixes — already landed

Three classes of source-level breakage had to be fixed before anything
compiled. They are all in place on `main`:

### 1. ZIPFoundation — Bionic libc imports

`import Foundation` does not transitively re-export Bionic the way it
re-exports Darwin / Glibc / ucrt. Files that used raw libc symbols
(`stat`, `lstat`, `S_IFMT`/`S_IFREG`/`S_IFDIR`/`S_IFLNK`, `mode_t`,
`fopen`/`fclose`/`fread`/`fwrite`/`fseeko`/`ftello`, `fileno`,
`ftruncate`, `time_t`/`gmtime`/`timegm`, `timeval`/`timespec`,
`fpos_t`, `funopen`, `FILE`, `errno`) failed with "cannot find … in
scope".

Tracked in [weichsel/ZIPFoundation#380](https://github.com/weichsel/ZIPFoundation/pull/380).
While that PR is open, `Package.swift` pins
[`odrobnik/ZIPFoundation@fix/android-windows-imports`](https://github.com/odrobnik/ZIPFoundation/tree/fix/android-windows-imports),
which:

- Adds `canImport(Android)` / `canImport(Bionic)` shims to every source
  file that touches raw libc.
- Wraps `setSymlinkPermissions` / `setSymlinkModificationDate` in their
  existing Apple-only `#if`. Bionic ships neither `lchmod` nor a usable
  `lutimes` for symlinks; Linux's `lchmod` is a kernel no-op anyway, so
  the call sites are already Apple-gated — only the definitions weren't.
- Guards the `fwrite(buffer.baseAddress, …)` empty-buffer case for
  Bionic's stricter non-optional `UnsafeRawPointer` parameter.
- Routes Android's `MemoryFile` through `fopencookie` instead of
  `funopen`. Bionic's `funopen` is `__INTRODUCED_IN(28)` and trips
  `undefined symbol: funopen` on lower API targets; `fopencookie` is
  available since API 23.

Once upstream merges, flip the dep back to `weichsel/ZIPFoundation` and
delete the fork branch.

### 2. ForgeKit — `isatty` import

[`Sources/ForgeKit/IO/TTY.swift`](../Sources/ForgeKit/IO/TTY.swift) calls
`isatty(2)`. The same `canImport(Android)` / `canImport(Bionic)` block
already used for Glibc/Musl was missing. Fixed by extending the shim.

### 3. SwiftGit — `GIT_REBASE_NO_OPERATION` macro

`libgit2`'s `git2/rebase.h` `#define`s `GIT_REBASE_NO_OPERATION SIZE_MAX`.
The Swift macro importer surfaces it on Apple/Linux but drops it on the
Android SDK, so `Int(GIT_REBASE_NO_OPERATION)` failed with "cannot find
… in scope".

[`GitClient+Rebase.swift:115-118`](../Sources/SwiftGit/Lib/GitClient+Rebase.swift#L115-L118)
now compares in `size_t` space and short-circuits on `size_t.max` before
narrowing to `Int`. This also fixes a latent overflow trap that already
existed on every platform: when libgit2 actually returns the sentinel,
`Int.init(_:)` traps because `SIZE_MAX` doesn't fit in a signed `Int64`.

## Outstanding — executable + test linking

### The blocker

Even with every library compiling, `swift build` fails the moment it
tries to link an executable on Android:

```
[…/…] Linking zip
ld.lld: error: undefined symbol: __libc_init
clang: error: linker command failed with exit code 1
```

`__libc_init` is the Bionic CRT entry point — it lives in
`crtbegin_dynamic.o` from the NDK. It needs to be passed explicitly to
the linker for any standalone Bionic ELF executable. The Swift Android
SDK's link recipe (or `skiptools/swift-android-action`'s wrapper around
it) doesn't pull that startup object into the link line for SwiftPM
executable targets.

Test bundles hit the same path — they're test executables, not shared
libraries.

### Workaround in CI

`.github/workflows/swift.yml` → `build-android`:

- Restricts the build to library `--target`s.
- `build-tests: false` and `run-tests: false` on the action — no test
  bundle assembly, no emulator boot.

This is fine for the realistic Android consumer (SwiftBash embedding
SwiftPorts libraries inside a Bash builtin); standalone CLI tools are
not a real Android use case.

### Fix path

Either upstream:

1. `skiptools/swift-android-action` adds the missing CRT objects /
   linker flags so Swift executable targets actually link.
2. The Swift Android SDK's `swiftpm-android` integration handles
   executable products natively.

Once either lands, drop the `--target` filter, set `build-tests: true`
and `run-tests: true` on the action, and watch the executables + test
bundles light up.

## CI workflow

`.github/workflows/swift.yml` → `build-android`:

- `skiptools/swift-android-action@v2`, Swift 6.3.
- `free-disk-space: true` — the SDK + NDK + emulator together push past
  the runner's ~14 GiB free without cleanup.
- `swift-build-flags` lists every library target (with deps that ripple
  in transitively).
- `build-tests: false`, `run-tests: false` — no emulator phase.

## Adding a new Android-buildable target

If you add a library target whose source compiles on Bionic, append it
to the `--target` list in `build-android`. Watch for fresh
`cannot find 'foo' in scope` errors — they usually mean another libc
symbol that needs `import Android` / `import Bionic` somewhere. The
shim block to copy is:

```swift
#if canImport(Android)
import Android
#elseif canImport(Bionic)
import Bionic
#endif
```

If you add an executable target, expect `__libc_init` until the link
recipe is fixed upstream — leave it out of the Android list for now.
