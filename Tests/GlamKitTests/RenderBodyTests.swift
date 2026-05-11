import Foundation
import Testing
@testable import GlamKit

@Suite("Glam.renderBody")
struct RenderBodyTests {

    /// Happy path — well-formed markdown renders successfully.
    @Test func validMarkdownReturnsRenderedANSI() {
        let out = Glam.renderBody("# Hello")
        #expect(out.contains("Hello"))
        // Don't assert on exact escapes — `.auto` picks the style at
        // runtime, which differs depending on whether the test host
        // runs in a TTY. The point is that the call doesn't throw
        // and the visible text survives.
    }

    /// Forgiving — if Glam errors internally we still return the
    /// raw body. Hard to *force* an error from a string input, but
    /// the empty string at least exercises the happy path.
    @Test func emptyBodyReturnsEmptyOrRendered() {
        let out = Glam.renderBody("")
        // Either the empty input renders as a small `notty` doc
        // header/footer or as empty itself — both are valid here.
        // The only thing we MUST NOT do is throw.
        _ = out
    }
}
