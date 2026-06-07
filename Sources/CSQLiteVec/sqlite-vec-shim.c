// Compiles the vendored sqlite-vec amalgamation as this target's single
// translation unit while keeping sqlite-vec.c byte-for-byte upstream.
//
// sqlite-vec.c calls va_start but only pulls <stdarg.h> in transitively, via
// sqlite3.h. Under SwiftPM, sqlite3.h is consumed as a Clang module, and a
// module's macros (va_start) do not cross into this unit — so the amalgamation
// fails to compile on its own with "va_start undeclared". Including <stdarg.h>
// directly here, before the amalgamation, supplies the macro without patching
// the vendored file. (Functions/types from sqlite3.h cross the module boundary
// fine; only the macro needed help.)
//
// sqlite-vec.c is `exclude`d from the target's own source list in Package.swift
// and pulled in here instead, so it stays a clean drop-in on the next update.
#include <stdarg.h>

#include "csqlite_vec.h"
#include "sqlite-vec.c"   // defines sqlite3_vec_init (built with -DSQLITE_CORE)

int csqlite_vec_register(void) {
    // The generic void(*)(void) cast is the documented sqlite-vec static-
    // registration idiom; SQLite casts the entry point back internally.
    return sqlite3_auto_extension((void (*)(void))sqlite3_vec_init);
}
