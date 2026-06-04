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
        // SQLite's CSV mode uses CRLF row terminators, including a trailing one.
        let formatter = ResultFormatter(mode: .csv, showHeader: true)
        #expect(formatter.render(sample) == "id,name\r\n1,alice\r\n2,\r\n")
    }

    @Test func csvQuoting() {
        let set = ResultSet(columns: ["x"], rows: [[.text("a,b")], [.text("he\"llo")]])
        let formatter = ResultFormatter(mode: .csv)
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
}
