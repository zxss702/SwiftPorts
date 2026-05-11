import Foundation
import Testing
@testable import ForgeKit

@Suite("StatusBadge")
struct StatusBadgeTests {

    private let GREEN   = "\u{1B}[32m"
    private let RED     = "\u{1B}[31m"
    private let YELLOW  = "\u{1B}[33m"
    private let MAGENTA = "\u{1B}[35m"
    private let RESET   = "\u{1B}[m"

    @Test func enabledColorsByState() {
        #expect(StatusBadge.open()       == "\(GREEN)open\(RESET)")
        #expect(StatusBadge.closed()     == "\(MAGENTA)closed\(RESET)")
        #expect(StatusBadge.merged()     == "\(MAGENTA)merged\(RESET)")
        #expect(StatusBadge.draft()      == "\(YELLOW)draft\(RESET)")
        #expect(StatusBadge.success()    == "\(GREEN)success\(RESET)")
        #expect(StatusBadge.failure()    == "\(RED)failure\(RESET)")
        #expect(StatusBadge.inProgress() == "\(YELLOW)in_progress\(RESET)")
    }

    @Test func customLabelOverridesDefault() {
        #expect(StatusBadge.open("opened")    == "\(GREEN)opened\(RESET)")
        #expect(StatusBadge.draft("(draft)")  == "\(YELLOW)(draft)\(RESET)")
    }

    @Test func disabledIsPassthrough() {
        #expect(StatusBadge.open(enabled: false)    == "open")
        #expect(StatusBadge.closed(enabled: false)  == "closed")
        #expect(StatusBadge.merged(enabled: false)  == "merged")
    }

    @Test func emptyInputNoOps() {
        #expect(StatusBadge.muted("") == "")
    }
}

@Suite("LabelChip")
struct LabelChipTests {

    @Test func disabledIsPassthrough() {
        #expect(LabelChip.colored(name: "bug", hex: "ff0000", enabled: false) == "bug")
    }

    @Test func noHexFallsBackToPlainName() {
        #expect(LabelChip.colored(name: "bug", hex: nil, enabled: true, trueColor: true) == "bug")
    }

    @Test func malformedHexFallsBackToPlainName() {
        #expect(LabelChip.colored(name: "bug", hex: "zzz", enabled: true, trueColor: true) == "bug")
    }

    @Test func nonTrueColorTerminalFallsBackToPlainName() {
        #expect(LabelChip.colored(name: "bug", hex: "ff0000", enabled: true, trueColor: false) == "bug")
    }

    @Test func trueColorRendersBackground24bitForeground256() {
        // Red background; perceived luminance ≈ 0.299 < 0.5, so foreground 255 (white).
        let out = LabelChip.colored(name: "bug", hex: "ff0000", enabled: true, trueColor: true)
        #expect(out.contains("48;2;255;0;0"))
        #expect(out.contains("38;5;255"))
        #expect(out.contains(" bug "), "expected padding around label: \(out)")
    }

    @Test func brightLabelGetsBlackForeground() {
        // Yellow background; perceived luminance ≈ 0.886 > 0.5, so fg 0 (black).
        let out = LabelChip.colored(name: "wip", hex: "ffff00", enabled: true, trueColor: true)
        #expect(out.contains("38;5;0"))
    }

    @Test func hexPrefixIsTolerated() {
        let withHash = LabelChip.colored(name: "x", hex: "#ff0000", enabled: true, trueColor: true)
        let without  = LabelChip.colored(name: "x", hex: "ff0000",  enabled: true, trueColor: true)
        #expect(withHash == without)
    }
}
