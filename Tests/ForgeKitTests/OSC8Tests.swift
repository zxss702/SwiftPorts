import Foundation
import Testing
@testable import ForgeKit

@Suite("OSC8")
struct OSC8Tests {

    @Test func disabledIsPassthrough() {
        #expect(OSC8.wrap("#42", url: "https://x.example", enabled: false) == "#42")
    }

    @Test func enabledWrapsWithEscapes() {
        let out = OSC8.wrap("#42", url: "https://x.example", enabled: true)
        #expect(out.hasPrefix("\u{1B}]8;id="))
        #expect(out.contains(";https://x.example\u{1B}\\"))
        #expect(out.hasSuffix("\u{1B}]8;;\u{1B}\\"))
        // The visible text must still be present between the escapes
        // — terminals that don't support OSC 8 see it as-is.
        #expect(out.contains("#42"))
    }

    @Test func emptyURLNoOps() {
        // Empty URL is meaningless for a hyperlink — return text plain.
        #expect(OSC8.wrap("foo", url: "", enabled: true) == "foo")
    }

    @Test func sameURLProducesSameID() {
        // The `id=` parameter is an FNV-1a hash of the URL. Two calls
        // with the same URL must produce identical openers so terminals
        // can group occurrences.
        let a = OSC8.wrap("a", url: "https://example.com", enabled: true)
        let b = OSC8.wrap("b", url: "https://example.com", enabled: true)
        let aOpener = String(a.prefix(while: { $0 != "\u{1B}" || true }).prefix(40))
        let bOpener = String(b.prefix(while: { $0 != "\u{1B}" || true }).prefix(40))
        // Trim text portion: openers should be byte-identical.
        let aId = a.components(separatedBy: ";").prefix(2).joined(separator: ";")
        let bId = b.components(separatedBy: ";").prefix(2).joined(separator: ";")
        #expect(aId == bId, "different IDs for same URL: \(aOpener) vs \(bOpener)")
    }
}
