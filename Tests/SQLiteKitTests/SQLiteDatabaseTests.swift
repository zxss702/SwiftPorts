import Foundation
import Testing
@testable import SQLiteKit

@Suite struct SQLiteDatabaseTests {

    @Test func crudRoundTrip() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT NOT NULL, qty INTEGER);")
        try db.evaluate("INSERT INTO t(name, qty) VALUES ('apple', 3), ('banana', 5);")
        try db.evaluate("UPDATE t SET qty = qty + 1 WHERE name = 'apple';")
        try db.evaluate("DELETE FROM t WHERE name = 'banana';")

        let sets = try db.evaluate("SELECT id, name, qty FROM t ORDER BY id;")
        #expect(sets.count == 1)
        #expect(sets[0].columns == ["id", "name", "qty"])
        #expect(sets[0].rows == [[.integer(1), .text("apple"), .integer(4)]])
    }

    // Vector / semantic search via the vendored sqlite-vec (the `SQLiteVec`
    // package trait, off by default). Mirrors the real workflow: embeddings
    // come from some external model, are L2-normalized to unit vectors, and
    // stored in a `vec0` table for cosine KNN — the scale that fits on an
    // iPhone/iPad. SwiftPM defines the `SQLiteVec` compilation condition
    // exactly when the trait is on, so run the positive path with
    // `swift test --traits SQLiteVec`.
    @Test func semanticSearchSQLiteVec() throws {
        let db = try SQLiteDatabase.inMemory()
        #if SQLiteVec
        // Trait on: sqlite-vec is compiled in and auto-registered.
        #expect(try db.evaluate("SELECT vec_version();")[0].rows[0][0] == .text("v0.1.9"))

        // A small semantic-lookup table: three unit vectors standing in for
        // document embeddings, compared by cosine distance.
        try db.evaluate("""
            CREATE VIRTUAL TABLE docs USING vec0(
                doc_id INTEGER PRIMARY KEY,
                embedding float[3] distance_metric=cosine
            );
            INSERT INTO docs(doc_id, embedding) VALUES
              (1, '[1.0, 0.0, 0.0]'),   -- e.g. "cat"
              (2, '[0.0, 1.0, 0.0]'),   -- e.g. "car"
              (3, '[0.0, 0.0, 1.0]');   -- e.g. "sky"
            """)

        // KNN: a query vector nearest doc 1, then doc 2 (doc 3 is orthogonal).
        let knn = try db.evaluate("""
            SELECT doc_id FROM docs
            WHERE embedding MATCH '[0.9, 0.1, 0.0]' AND k = 2
            ORDER BY distance;
            """)
        #expect(knn[0].rows.map { $0[0] } == [.integer(1), .integer(2)])
        #else
        // Trait off (the default): the vec0 module is not registered.
        #expect(throws: SQLiteError.self) {
            try db.evaluate("CREATE VIRTUAL TABLE v USING vec0(embedding float[3]);")
        }
        #endif
    }

    @Test func quoteIdentifierMatchesSqlite() {
        // Bare for simple identifiers; double-quoted (embedded " doubled) for
        // names with special characters or that collide with a SQL keyword.
        #expect(SQLiteDatabase.quoteIdentifier("foo") == "foo")
        #expect(SQLiteDatabase.quoteIdentifier("My_Tab2") == "My_Tab2")
        #expect(SQLiteDatabase.quoteIdentifier("order") == "\"order\"")          // keyword
        #expect(SQLiteDatabase.quoteIdentifier("ORDER") == "\"ORDER\"")          // keyword, case-insensitive
        #expect(SQLiteDatabase.quoteIdentifier("my table") == "\"my table\"")    // space
        #expect(SQLiteDatabase.quoteIdentifier("weird-name") == "\"weird-name\"") // dash
        #expect(SQLiteDatabase.quoteIdentifier("a\"b") == "\"a\"\"b\"")          // embedded quote doubled
        #expect(SQLiteDatabase.quoteIdentifier("1abc") == "\"1abc\"")            // leading digit
    }

    @Test func valueTypeMapping() throws {
        let db = try SQLiteDatabase.inMemory()
        let row = try db.evaluate("SELECT 1, 2.5, 'hi', NULL, x'00ff';")[0].rows[0]
        #expect(row[0] == .integer(1))
        #expect(row[1] == .real(2.5))
        #expect(row[2] == .text("hi"))
        #expect(row[3] == .null)
        if case .blob(let data) = row[4] {
            #expect(Array(data) == [0x00, 0xff])
        } else {
            Issue.record("expected a blob value")
        }
    }

    @Test func lastInsertRowIDAndChanges() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT);")
        try db.evaluate("INSERT INTO t(v) VALUES ('a'), ('b'), ('c');")
        #expect(db.lastInsertRowID == 3)
        try db.evaluate("UPDATE t SET v = 'x';")
        #expect(db.changes == 3)
    }

    @Test func introspection() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("""
            CREATE TABLE alpha(id INTEGER);
            CREATE TABLE beta(id INTEGER);
            CREATE VIEW v AS SELECT 1;
            """)
        #expect(try db.tableNames() == ["alpha", "beta", "v"])
        let schema = try db.schemaSQL(of: "alpha")
        #expect(schema.count == 1)
        #expect(schema[0].contains("CREATE TABLE alpha"))
    }

    @Test func schemaIncludesIndexesAndTriggers() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("""
            CREATE TABLE foo(id INTEGER, x TEXT);
            CREATE INDEX idx ON foo(x);
            CREATE TRIGGER tr AFTER INSERT ON foo BEGIN SELECT 1; END;
            """)
        let schema = try db.schemaSQL(of: "foo")
        #expect(schema.count == 3)
        #expect(schema[0].contains("CREATE TABLE foo"))
        #expect(schema.contains { $0.contains("CREATE INDEX idx") })
        #expect(schema.contains { $0.contains("CREATE TRIGGER tr") })
    }

    @Test func multiStatementResultSets() throws {
        let db = try SQLiteDatabase.inMemory()
        let sets = try db.evaluate("SELECT 1 AS a; SELECT 2 AS b, 3 AS c;")
        #expect(sets.count == 2)
        #expect(sets[0].columns == ["a"])
        #expect(sets[1].columns == ["b", "c"])
        #expect(sets[1].rows == [[.integer(2), .integer(3)]])
    }

    @Test func errorSurface() throws {
        let db = try SQLiteDatabase.inMemory()
        #expect(throws: SQLiteError.self) {
            try db.evaluate("SELECT * FROM nope;")
        }
    }

    @Test func vendoredVersionIsPinned() {
        #expect(SQLiteDatabase.libVersion == "3.50.4")
    }

    // MARK: - Parameter binding (issue #52)

    @Test func boundEvaluateRoundTripsEverySQLiteValueCase() throws {
        let db = try SQLiteDatabase.inMemory()
        let blob = Data([0x00, 0x01, 0xfe, 0xff])
        // One bound SELECT carrying every storage class straight back out.
        let row = try db.evaluate(
            "SELECT ?, ?, ?, ?, ?;",
            [.null, .integer(42), .real(2.5), .text("héllo"), .blob(blob)]
        )[0].rows[0]
        #expect(row == [.null, .integer(42), .real(2.5), .text("héllo"), .blob(blob)])
    }

    @Test func boundTextNeedsNoEscaping() throws {
        // A value full of single quotes that would break the string path binds
        // losslessly — the whole point of out-of-band parameters.
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("CREATE TABLE t(v TEXT);")
        let nasty = "Bobby '); DROP TABLE t; -- ''"
        try db.execute("INSERT INTO t(v) VALUES (?);", [.text(nasty)])
        let rows = try db.evaluate("SELECT v FROM t;")[0].rows
        #expect(rows == [[.text(nasty)]])
    }

    @Test func boundEmptyBlobStaysABlob() throws {
        // Empty Data must bind as a zero-length blob, not SQL NULL.
        let db = try SQLiteDatabase.inMemory()
        let row = try db.evaluate("SELECT ?;", [.blob(Data())])[0].rows[0]
        #expect(row == [.blob(Data())])
    }

    @Test func preparedStatementReuseAcrossRows() throws {
        // Prepare once, step many: one INSERT … VALUES(?, ?) bound in a loop.
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT);")
        let stmt = try SQLiteStatement(db, "INSERT INTO t(id, name) VALUES (?, ?);")
        let people: [(Int64, String)] = [(1, "a"), (2, "b"), (3, "c")]
        for (id, name) in people {
            try stmt.bind([.integer(id), .text(name)])
            _ = try stmt.step()
            stmt.reset()
        }
        let sets = try db.evaluate("SELECT id, name FROM t ORDER BY id;")
        #expect(sets[0].rows == [[.integer(1), .text("a")],
                                 [.integer(2), .text("b")],
                                 [.integer(3), .text("c")]])
    }

    @Test func preparedStatementIteratesResultRows() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("CREATE TABLE t(n INTEGER);")
        try db.execute("INSERT INTO t(n) VALUES (1),(2),(3);")
        let stmt = try SQLiteStatement(db, "SELECT n FROM t WHERE n >= ? ORDER BY n;")
        try stmt.bind([.integer(2)])
        var seen: [Int64] = []
        while let row = try stmt.step() {
            if case .integer(let n) = row[0] { seen.append(n) }
        }
        #expect(seen == [2, 3])
    }

    @Test func namedParameterBinding() throws {
        let db = try SQLiteDatabase.inMemory()
        let row = try db.evaluate(
            "SELECT :a + :b AS sum, :a AS a;",
            [":a": .integer(10), ":b": .integer(5)]
        )[0].rows[0]
        #expect(row == [.integer(15), .integer(10)])
    }

    @Test func unknownNamedParameterThrows() throws {
        let db = try SQLiteDatabase.inMemory()
        let stmt = try SQLiteStatement(db, "SELECT :a;")
        #expect(throws: SQLiteError.self) {
            try stmt.bind(":nope", .integer(1))
        }
    }

    @Test func parameterCountMismatchThrowsBeforeStepping() throws {
        let db = try SQLiteDatabase.inMemory()
        let stmt = try SQLiteStatement(db, "SELECT ?, ?;")
        #expect(throws: SQLiteError.self) {
            try stmt.bind([.integer(1)])           // too few
        }
        #expect(throws: SQLiteError.self) {
            try stmt.bind([.integer(1), .integer(2), .integer(3)])   // too many
        }
    }

    @Test func boundPathRejectsMultipleStatements() throws {
        let db = try SQLiteDatabase.inMemory()
        // Trailing whitespace / a bare terminator is fine…
        #expect(throws: Never.self) {
            try SQLiteStatement(db, "SELECT 1;  ")
        }
        // …but a real second statement can't be bound unambiguously.
        #expect(throws: SQLiteError.self) {
            try SQLiteStatement(db, "SELECT 1; SELECT 2;")
        }
    }

    // The compact `vec0` insert path: a packed float32 blob bound out-of-band
    // (6 KB of raw bytes for a 1536-d vector instead of a ~20 KB JSON literal),
    // then MATCH KNN reads it back — proving the blob bind end-to-end. Gated on
    // the SQLiteVec trait; run with `swift test --traits SQLiteVec`.
    @Test func vec0BlobBind() throws {
        let db = try SQLiteDatabase.inMemory()
        #if SQLiteVec
        try db.evaluate("""
            CREATE VIRTUAL TABLE docs USING vec0(
                doc_id INTEGER PRIMARY KEY,
                embedding float[3] distance_metric=cosine
            );
            """)

        func packed(_ floats: [Float]) -> Data {
            var data = Data(capacity: floats.count * 4)
            for f in floats {
                var le = f.bitPattern.littleEndian
                withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
            }
            return data
        }

        // Prepare once, bind a packed-float32 blob per row.
        let insert = try SQLiteStatement(db, "INSERT INTO docs(doc_id, embedding) VALUES (?, ?);")
        let vectors: [(Int64, [Float])] = [(1, [1, 0, 0]), (2, [0, 1, 0]), (3, [0, 0, 1])]
        for (id, vector) in vectors {
            try insert.bind([.integer(id), .blob(packed(vector))])
            _ = try insert.step()
            insert.reset()
        }

        // KNN with the query vector itself bound as a blob parameter.
        let knn = try db.evaluate("""
            SELECT doc_id FROM docs
            WHERE embedding MATCH ? AND k = 2
            ORDER BY distance;
            """, [.blob(packed([0.9, 0.1, 0.0]))])
        #expect(knn[0].rows.map { $0[0] } == [.integer(1), .integer(2)])
        #else
        #expect(throws: SQLiteError.self) {
            try db.evaluate("CREATE VIRTUAL TABLE v USING vec0(embedding float[3]);")
        }
        #endif
    }

    // FTS5 full-text search, gated by the package's `FTS5` trait (off by
    // default). The test pins the on/off contract in both directions: with
    // the trait, the engine advertises ENABLE_FTS5 and MATCH works; without
    // it, the module is absent and `USING fts5(...)` fails. SwiftPM defines
    // the `FTS5` compilation condition for this target exactly when the trait
    // is enabled, so run the positive path with `swift test --traits FTS5`.
    @Test func fullTextSearchFTS5() throws {
        let db = try SQLiteDatabase.inMemory()
        let options = try db.evaluate("PRAGMA compile_options;")[0].rows.map { $0[0] }
        #if FTS5
        // Trait enabled: the flag is baked into the engine.
        #expect(options.contains(.text("ENABLE_FTS5")))

        try db.evaluate("""
            CREATE VIRTUAL TABLE docs USING fts5(title, body);
            INSERT INTO docs(title, body) VALUES
              ('SQLite FTS', 'Full text search. Full ranking. Full speed.'),
              ('Swift Pkgs', 'SwiftPM traits toggle compile-time features.'),
              ('Gardening',  'Tomatoes need full sun and regular watering.');
            """)

        // Single-term MATCH hits only the row containing the term.
        let hit = try db.evaluate("SELECT title FROM docs WHERE docs MATCH 'search';")
        #expect(hit[0].rows == [[.text("SQLite FTS")]])

        // Column filter: `body:compile` only matches within the body column.
        let col = try db.evaluate("SELECT title FROM docs WHERE docs MATCH 'body:compile';")
        #expect(col[0].rows == [[.text("Swift Pkgs")]])

        // Boolean AND requires both terms in the same row.
        let both = try db.evaluate("SELECT title FROM docs WHERE docs MATCH 'full AND text';")
        #expect(both[0].rows == [[.text("SQLite FTS")]])

        // bm25 ranking: more occurrences of the term rank higher. "full"
        // appears 3× in the SQLite row, 1× in the Gardening row, so ORDER BY
        // rank returns SQLite first.
        let ranked = try db.evaluate("SELECT title FROM docs WHERE docs MATCH 'full' ORDER BY rank;")
        #expect(ranked[0].rows.map { $0[0] } == [.text("SQLite FTS"), .text("Gardening")])
        #else
        // Trait disabled (the default build): the module must not be present.
        #expect(!options.contains(.text("ENABLE_FTS5")))
        #expect(throws: SQLiteError.self) {
            try db.evaluate("CREATE VIRTUAL TABLE docs USING fts5(x);")
        }
        #endif
    }
}

@Suite struct ResultFormatterTests {
    private let sample = ResultSet(
        columns: ["id", "name"],
        rows: [[.integer(1), .text("alice")], [.integer(2), .null]])

    @Test func listMode() {
        var formatter = ResultFormatter(mode: .list)
        #expect(formatter.render(sample) == "1|alice\n2|\n")
        formatter.showHeader = true
        #expect(formatter.render(sample) == "id|name\n1|alice\n2|\n")
    }

    @Test func listNullValue() {
        let formatter = ResultFormatter(mode: .list, nullValue: "NULL")
        #expect(formatter.render(sample) == "1|alice\n2|NULL\n")
    }

    @Test func csvMode() {
        // The `.mode csv` dot-command uses CRLF row terminators (set via
        // rowSeparator); the `-csv` flag uses LF — see csvFlagUsesLF.
        let formatter = ResultFormatter(mode: .csv, showHeader: true, rowSeparator: "\r\n")
        #expect(formatter.render(sample) == "id,name\r\n1,alice\r\n2,\r\n")
    }

    @Test func csvQuoting() {
        let set = ResultSet(columns: ["x"], rows: [[.text("a,b")], [.text("he\"llo")]])
        let formatter = ResultFormatter(mode: .csv, rowSeparator: "\r\n")
        #expect(formatter.render(set) == "\"a,b\"\r\n\"he\"\"llo\"\r\n")
    }

    @Test func jsonMode() {
        let formatter = ResultFormatter(mode: .json)
        #expect(formatter.render(sample) == "[{\"id\":1,\"name\":\"alice\"},\n{\"id\":2,\"name\":null}]\n")
    }

    @Test func jsonBlob() {
        // SQLite renders BLOBs in JSON as one \u00XX escape per byte.
        let set = ResultSet(columns: ["b"], rows: [[.blob(Data([0x00, 0xff]))]])
        let formatter = ResultFormatter(mode: .json)
        #expect(formatter.render(set) == "[{\"b\":\"\\u0000\\u00ff\"}]\n")
    }

    @Test func columnMode() {
        let formatter = ResultFormatter(mode: .column, showHeader: true)
        let output = formatter.render(sample)
        #expect(output.contains("id  name"))
        #expect(output.contains("--  -----"))
        #expect(output.contains("1   alice"))
    }

    @Test func tabsMode() {
        let formatter = ResultFormatter(mode: .tabs, showHeader: true)
        #expect(formatter.render(sample) == "id\tname\n1\talice\n2\t\n")
    }

    @Test func asciiMode() {
        let formatter = ResultFormatter(mode: .ascii)
        #expect(formatter.render(sample) == "1\u{1F}alice\u{1E}2\u{1F}\u{1E}")
    }

    @Test func htmlMode() {
        let formatter = ResultFormatter(mode: .html, showHeader: true)
        #expect(formatter.render(sample) == "<TR><TH>id</TH>\n<TH>name</TH>\n</TR>\n<TR><TD>1</TD>\n<TD>alice</TD>\n</TR>\n<TR><TD>2</TD>\n<TD></TD>\n</TR>\n")
    }

    @Test func markdownMode() {
        let formatter = ResultFormatter(mode: .markdown, showHeader: true)
        #expect(formatter.render(sample) == "| id | name  |\n|----|-------|\n| 1  | alice |\n| 2  |       |\n")
    }

    @Test func tableMode() {
        let formatter = ResultFormatter(mode: .table, showHeader: true)
        #expect(formatter.render(sample) == "+----+-------+\n| id | name  |\n+----+-------+\n| 1  | alice |\n| 2  |       |\n+----+-------+\n")
    }

    @Test func boxMode() {
        let formatter = ResultFormatter(mode: .box, showHeader: true)
        #expect(formatter.render(sample) == "┌────┬───────┐\n│ id │ name  │\n├────┼───────┤\n│ 1  │ alice │\n│ 2  │       │\n└────┴───────┘\n")
    }

    @Test func quoteMode() {
        let formatter = ResultFormatter(mode: .quote, showHeader: true)
        #expect(formatter.render(sample) == "'id','name'\n1,'alice'\n2,NULL\n")
    }

    @Test func insertMode() {
        var formatter = ResultFormatter(mode: .insert)
        #expect(formatter.render(sample) == "INSERT INTO \"table\" VALUES(1,'alice');\nINSERT INTO \"table\" VALUES(2,NULL);\n")
        formatter.insertTable = "t"
        #expect(formatter.render(sample) == "INSERT INTO t VALUES(1,'alice');\nINSERT INTO t VALUES(2,NULL);\n")
    }

    @Test func sqlLiteralSerialization() {
        #expect(SQLiteValue.text("a'b").sqlLiteral == "'a''b'")
        #expect(SQLiteValue.blob(Data([0x00, 0xff])).sqlLiteral == "X'00ff'")
        #expect(SQLiteValue.null.sqlLiteral == "NULL")
        #expect(SQLiteValue.integer(42).sqlLiteral == "42")
    }

    @Test func insertModeWithHeadersListsColumns() {
        // With headers on, sqlite3's insert mode prefixes the column list.
        let formatter = ResultFormatter(mode: .insert, showHeader: true)
        #expect(formatter.render(sample) ==
            "INSERT INTO \"table\"(id,name) VALUES(1,'alice');\nINSERT INTO \"table\"(id,name) VALUES(2,NULL);\n")
    }

    @Test func realTextMatchesSqlite() {
        // Text/display modes use sqlite3's %!.15g: 15 significant digits,
        // always float-shaped, with -0.0 normalized to 0.0.
        #expect(SQLiteValue.realText(1.0 / 3.0) == "0.333333333333333")
        #expect(SQLiteValue.realText(0.1 + 0.2) == "0.3")
        #expect(SQLiteValue.realText(100) == "100.0")
        #expect(SQLiteValue.realText(-0.0) == "0.0")
        #expect(SQLiteValue.realText(1e20) == "1.0e+20")
        #expect(SQLiteValue.realText(2.5) == "2.5")
        // ...and it flows through text-mode rendering (was String(d) before):
        let set = ResultSet(columns: ["r"], rows: [[.real(1.0 / 3.0)]])
        #expect(ResultFormatter(mode: .list).render(set) == "0.333333333333333\n")
    }

    @Test func boxCentersHeadersOverWiderData() {
        // sqlite3 centers headers (data stays left-justified) in box mode.
        let set = ResultSet(columns: ["x", "y"], rows: [[.integer(1), .text("longvalue")]])
        let formatter = ResultFormatter(mode: .box, showHeader: true)
        #expect(formatter.render(set) ==
            "┌───┬───────────┐\n│ x │     y     │\n├───┼───────────┤\n│ 1 │ longvalue │\n└───┴───────────┘\n")
    }

    @Test func lineModeHasMinimumWidth() {
        // sqlite3 right-justifies the column name in a field at least 5 wide.
        let set = ResultSet(columns: ["a"], rows: [[.integer(1)]])
        #expect(ResultFormatter(mode: .line).render(set) == "    a = 1\n")
    }

    // MARK: - Parity batch (issue #43)

    @Test func realLiteralMatchesSqliteDtoa() {
        // Full-precision round-trip rendering via the engine's %!.20g.
        #expect(SQLiteValue.realLiteral(0.1 + 0.2) == "0.3000000000000000445")
        #expect(SQLiteValue.realLiteral(3.14) == "3.140000000000000124")
        #expect(SQLiteValue.realLiteral(1e20) == "1.0e+20")
    }

    @Test func nonGeneratedColumnsExcludesGenerated() throws {
        let db = try SQLiteDatabase.inMemory()
        try db.evaluate("CREATE TABLE t(a INT, g INT GENERATED ALWAYS AS (a+1) VIRTUAL, b TEXT);")
        #expect(try db.nonGeneratedColumns(of: "t") == ["a", "b"])
    }

    @Test func columnModeWrapsLongValuesAtSixty() {
        let set = ResultSet(columns: ["s"], rows: [[.text(String(repeating: "x", count: 65))]])
        let lines = ResultFormatter(mode: .column, showHeader: false).render(set)
            .split(separator: "\n", omittingEmptySubsequences: false)
        #expect(String(lines[0]) == String(repeating: "x", count: 60))   // wrapped at the 60-col cap
    }

    @Test func widthRightJustifiesNegative() {
        let set = ResultSet(columns: ["x"], rows: [[.text("ab")]])
        let formatter = ResultFormatter(mode: .column, showHeader: false, widths: [-5])
        #expect(formatter.render(set) == "   ab\n")
    }
}
