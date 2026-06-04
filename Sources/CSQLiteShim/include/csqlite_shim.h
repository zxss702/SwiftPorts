#ifndef CSQLITE_SHIM_H
#define CSQLITE_SHIM_H

/// Render a double exactly as the `sqlite3` shell does in its round-trip
/// contexts (`.dump`, quote mode, insert mode, JSON): full precision via
/// the engine's own `"%!.20g"` printf extension (the `!` "alternate form"
/// flag, which Swift cannot pass through to a C variadic). This guarantees
/// byte-for-byte parity with sqlite3's dtoa rather than approximating it
/// with the platform formatter.
///
/// Returns a NUL-terminated string allocated with `sqlite3_malloc`; the
/// caller owns it and must release it with `sqlite3_free`. Returns NULL on
/// allocation failure.
char *csqlite_real_literal(double r);

#endif /* CSQLITE_SHIM_H */
