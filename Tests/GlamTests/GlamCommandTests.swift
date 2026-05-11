import Testing
import Foundation
@testable import GlamCommand
import GlamKit

@Suite struct GlamCommandTests {
    @Test func parseStyleHandlesBundled() {
        if case .bundled(.dark) = Glam.parseStyle("dark") {} else { Issue.record("expected .bundled(.dark)") }
        if case .bundled(.light) = Glam.parseStyle("LIGHT") {} else { Issue.record("expected .bundled(.light)") }
        if case .bundled(.notty) = Glam.parseStyle("none") {} else { Issue.record("expected .bundled(.notty)") }
        if case .auto = Glam.parseStyle("auto") {} else { Issue.record("expected .auto") }
    }

    @Test func parseStyleUnknownFallsBackToAuto() {
        if case .auto = Glam.parseStyle("definitely-not-a-style") {} else {
            Issue.record("expected .auto fallback")
        }
    }
}
