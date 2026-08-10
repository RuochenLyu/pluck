import AppKit
import SwiftUI
import XCTest

@testable import PluckApp

/// The checkerboard is the app's statement about transparency, and it used to make that
/// statement in white on every appearance — a light board under a dark UI is the brightest
/// thing on screen and reads as a blown-out cutout rather than as "nothing here".
@MainActor
final class CheckerboardTests: XCTestCase {
    private func brightness(_ color: NSColor) -> CGFloat {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return (srgb.redComponent + srgb.greenComponent + srgb.blueComponent) / 3
    }

    func testTheDarkBoardIsDark() {
        let dark = Checkerboard.colors(for: .dark)
        XCTAssertLessThan(brightness(dark.base), 0.3)
        XCTAssertLessThan(brightness(dark.square), 0.3)
    }

    func testTheLightBoardIsLight() {
        let light = Checkerboard.colors(for: .light)
        XCTAssertGreaterThan(brightness(light.base), 0.8)
        XCTAssertGreaterThan(brightness(light.square), 0.8)
    }

    /// Both boards need the two squares to differ, or there is no board — and the contrast
    /// has to stay small enough that the pattern reads as backdrop rather than as content.
    ///
    /// Visual language v2 narrows the upper bound hard: the old light board was white
    /// against 0.87 grey, a 13% step that made the pattern the loudest thing in a cell that
    /// exists to show a cutout. Both appearances now sit in a 3–7% band, which is where p3's
    /// board is. The floor stays — a board with no visible squares is a grey rectangle, and
    /// a grey rectangle is exactly what "this part is transparent" must not look like.
    func testBothBoardsAreFaintButPresent() {
        for scheme in [ColorScheme.light, .dark] {
            let colors = Checkerboard.colors(for: scheme)
            let gap = abs(brightness(colors.base) - brightness(colors.square))
            XCTAssertGreaterThan(gap, 0.03, "\(scheme)")
            XCTAssertLessThan(gap, 0.07, "\(scheme)")
        }
    }

    func testTheDarkBoardUsesTheSystemDarkGreys() {
        let dark = Checkerboard.colors(for: .dark)
        XCTAssertEqual(dark.base, NSColor.pluckHex(0x2C2C2E))
        XCTAssertEqual(dark.square, NSColor.pluckHex(0x3A3A3C))
    }

    /// The squares are small as well as faint. Both halves of "fine texture" have to hold:
    /// a 5%-contrast board drawn at 8pt still reads as stripes at thumbnail size, because
    /// the cell is only ~90pt across and eleven squares of anything is a pattern.
    func testTheBoardIsDrawnFine() {
        XCTAssertEqual(Checkerboard().square, Tokens.checkerSquare)
        XCTAssertLessThanOrEqual(Tokens.checkerSquare, 6)
    }
}
