#ifndef CSQLITE_VEC_H
#define CSQLITE_VEC_H

/// Compile sqlite-vec into the engine and register it via
/// `sqlite3_auto_extension`, so every SQLite connection opened afterwards
/// exposes the `vec0` virtual table and the `vec_*` scalar functions
/// (`vec_f32`, `vec_distance_cosine`, …). Call once before opening the first
/// connection; registering the same entry point again is harmless.
///
/// Returns `SQLITE_OK` on success. Only built when the `SQLiteVec` package
/// trait is enabled (off by default); `SQLiteKit` calls it from
/// `SQLiteDatabase.init` under `#if SQLiteVec`.
int csqlite_vec_register(void);

#endif /* CSQLITE_VEC_H */
