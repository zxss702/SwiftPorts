import Foundation
import Testing
import ShellKit
@testable import ForgeKit

@Suite("ColorChoice")
struct ColorChoiceTests {

    @Test func parsesCanonicalForms() {
        #expect(ColorChoice(argument: "auto")    == .auto)
        #expect(ColorChoice(argument: "always")  == .always)
        #expect(ColorChoice(argument: "never")   == .never)
    }

    @Test func acceptsBooleanAliases() {
        #expect(ColorChoice(argument: "true")  == .always)
        #expect(ColorChoice(argument: "false") == .never)
    }

    @Test func rejectsUnknownValues() {
        #expect(ColorChoice(argument: "rainbow") == nil)
    }

    @Test func alwaysAndNeverIgnoreEnvAndTTY() {
        #expect(ColorChoice.always.resolved() == true)
        #expect(ColorChoice.never.resolved()  == false)
    }

    /// Uses ShellKit's TaskLocal `Shell.current` to inject env without
    /// touching the process env — same pattern GlamKit tests use. Avoids
    /// `setenv` (not in scope on Windows under Swift 6.3+).
    @Test func autoHonorsNoColorEnv() {
        let shell = Shell(environment: Environment(variables: ["NO_COLOR": "1"]))
        Shell.$current.withValue(shell) {
            #expect(ColorChoice.auto.resolved() == false)
        }
    }

    @Test func autoHonorsCLICOLORForceEnv() {
        let shell = Shell(environment: Environment(variables: ["CLICOLOR_FORCE": "1"]))
        Shell.$current.withValue(shell) {
            #expect(ColorChoice.auto.resolved() == true)
        }
    }

    /// `NO_COLOR` is the kill switch — it must beat `CLICOLOR_FORCE`
    /// when both are set. Same precedence real git uses.
    @Test func noColorWinsOverCLICOLORForce() {
        let shell = Shell(environment: Environment(variables: [
            "NO_COLOR": "1",
            "CLICOLOR_FORCE": "1",
        ]))
        Shell.$current.withValue(shell) {
            #expect(ColorChoice.auto.resolved() == false)
        }
    }
}
