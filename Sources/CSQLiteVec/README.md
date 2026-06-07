# CSQLiteVec

Vendored [`sqlite-vec`](https://github.com/asg017/sqlite-vec) — a pure-C,
zero-dependency vector-search extension for SQLite — compiled **statically**
into the engine and registered through `sqlite3_auto_extension`. It backs
on-device semantic search: store embeddings (produced by any model) as
`float[N]` vectors in a `vec0` virtual table and run KNN queries with
`MATCH … AND k = N ORDER BY distance`.

Only built when the **`SQLiteVec`** package trait is enabled (off by default).

## Provenance — do not hand-edit `sqlite-vec.{c,h}`

| | |
|---|---|
| Upstream | https://github.com/asg017/sqlite-vec |
| Version  | **v0.1.9** (source commit `e9f598abfa0c06b328d8fe5da9c3760cce74be10`) |
| Artifact | `sqlite-vec-0.1.9-amalgamation.tar.gz` (release asset) |
| License  | MIT **or** Apache-2.0 (see `LICENSE-MIT`, `LICENSE-APACHE`) |

`sqlite-vec.c` / `sqlite-vec.h` are the upstream amalgamation, **unmodified**.
It is `exclude`d from direct compilation and pulled in by `sqlite-vec-shim.c`,
which first includes `<stdarg.h>` — sqlite-vec.c needs `va_start` but only gets
`<stdarg.h>` transitively through `sqlite3.h`, and under SwiftPM sqlite3.h is a
Clang module whose macros don't cross translation units. Keeping the include in
the shim leaves the amalgamation a clean drop-in.

To update, replace the two files and bump the version above — no re-patching:

```sh
VER=0.1.9
curl -fsSL "https://github.com/asg017/sqlite-vec/releases/download/v$VER/sqlite-vec-$VER-amalgamation.tar.gz" \
  | tar xz -C Sources/CSQLiteVec sqlite-vec.c sqlite-vec.h
```

## Build flags (set on the `CSQLiteVec` target)

- `SQLITE_CORE` — link against the core engine instead of the loadable
  `sqlite3ext.h` API-routine indirection.
- `SQLITE_VEC_STATIC` — empties the API export macro (no `__declspec(dllexport)`
  on Windows for a statically linked symbol).
- `SQLITE_VEC_OMIT_FS` — drops the filesystem-reaching helpers (`.npy` loading),
  keeping vector ops in-database to match this project's sandbox posture.

`csqlite_vec.h` / `sqlite-vec-shim.c` are this repo's thin registration shim,
not part of upstream.
