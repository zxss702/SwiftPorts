import Foundation
import Testing
@testable import GitHub
import ForgeKit

@Suite struct ANSITests {
    @Test func wrapIsInertWhenColourDisabled() {
        // Tests run without a TTY and without CLICOLOR_FORCE, so
        // ANSI.enabled is false. Wrapping must return the original
        // string with no escape codes.
        let wrapped = ANSI.wrap("hello", .red, .bold)
        #expect(wrapped == "hello")
    }

    @Test func bareCodesProduceNoAnsiSequences() {
        for s in [ANSI.red("x"), ANSI.green("x"), ANSI.bold("x"), ANSI.dim("x")] {
            #expect(!s.contains("\u{1B}["))
        }
    }
}
