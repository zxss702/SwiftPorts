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
}
