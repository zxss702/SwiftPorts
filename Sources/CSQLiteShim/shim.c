#include "csqlite_shim.h"
#include "sqlite3.h"

// The CSQLite module also exposes sqlite3ext.h, whose loadable-extension
// indirection redefines sqlite3_mprintf as `sqlite3_api->mprintf` (only
// valid inside a dynamically-loaded extension). We link the engine
// statically, so drop that macro and call the real exported function.
#undef sqlite3_mprintf

// Thin, non-variadic wrapper over sqlite3_mprintf so Swift can reach the
// engine's "%!.20g" float formatting (Swift can't call C variadics, and
// the "!" flag is a SQLite printf extension the platform printf lacks).
char *csqlite_real_literal(double r) {
    return sqlite3_mprintf("%!.20g", r);
}
