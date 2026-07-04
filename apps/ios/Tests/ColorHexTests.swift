import SwiftUI
import XCTest
@testable import PRVIO

// Unit tests for the Color(hex:) parser and companion helpers. The parsing
// branches (validity, prefix stripping, trimming) need no rendering; the
// round-trip and isLight checks use only unambiguous black/white/primary
// colors so they can't drift across color spaces. Run with Cmd+U.
final class ColorHexTests: XCTestCase {

    // MARK: - Valid parsing

    func testParsesSixDigitWithHash() {
        XCTAssertNotNil(Color(hex: "#3B82F6"))
    }

    func testParsesSixDigitWithoutHash() {
        XCTAssertNotNil(Color(hex: "3B82F6"))
    }

    func testParsesLowercaseHex() {
        XCTAssertNotNil(Color(hex: "#ffffff"))
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertNotNil(Color(hex: "  #00FF00\n"))
    }

    // MARK: - Invalid parsing

    func testRejectsThreeDigitShorthand() {
        // The parser requires exactly 6 hex digits; shorthand is unsupported.
        XCTAssertNil(Color(hex: "#FFF"))
    }

    func testRejectsEightDigitWithAlpha() {
        XCTAssertNil(Color(hex: "#FF00FF80"))
    }

    func testRejectsNonHexCharacters() {
        XCTAssertNil(Color(hex: "#GGGGGG"))
    }

    func testRejectsEmptyString() {
        XCTAssertNil(Color(hex: ""))
    }

    func testRejectsHashOnly() {
        XCTAssertNil(Color(hex: "#"))
    }

    // MARK: - Round-trip (unambiguous colors only)

    func testHexStringRoundTripBlackAndWhite() {
        XCTAssertEqual(Color(hex: "#000000")?.hexString(), "#000000")
        XCTAssertEqual(Color(hex: "#FFFFFF")?.hexString(), "#FFFFFF")
    }

    // MARK: - isLight

    func testIsLightForWhiteAndBlack() {
        XCTAssertTrue(Color(hex: "#FFFFFF")!.isLight)
        XCTAssertFalse(Color(hex: "#000000")!.isLight)
    }

    func testIsLightForSaturatedYellowAndBlue() {
        // Rec. 601 luminance: yellow (0.886) is light; pure blue (0.114) is dark.
        XCTAssertTrue(Color(hex: "#FFFF00")!.isLight)
        XCTAssertFalse(Color(hex: "#0000FF")!.isLight)
    }
}
