import XCTest
import SwiftUI
import AniliteKit
@testable import Anilite

final class ThemeTests: XCTestCase {
    func testClamp() {
        XCTAssertEqual(clamp01(-1), 0)
        XCTAssertEqual(clamp01(2), 1)
        XCTAssertEqual(clamp01(0.25), 0.25)
    }

    func testBrandPaletteIsReadable() {
        let p = Theme.defaultPalette
        XCTAssertGreaterThanOrEqual(p.accent.contrast(with: p.deep), 4.5)
    }
}
