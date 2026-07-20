import XCTest
@testable import PRVIO

// End-to-end proof that the in-app language switch actually resolves strings,
// running inside the real app bundle (the test target is hosted by PRVIO.app,
// so Bundle.main here is the shipping bundle with its compiled .lproj tables).
//
// These tests pin the two mechanisms the app relies on:
//  1. the language .lproj bundle (what the String(localized:) shim resolves
//     against — Foundation's `locale:` parameter does NOT pick the table),
//  2. the Bundle.main swizzle (what SwiftUI Text/ObjC lookups go through).
// If a toolchain or packaging change ever stops shipping the per-language
// tables, these fail in CI instead of on the user's phone.
final class LanguageResolutionTests: XCTestCase {

    override func tearDown() {
        LanguageManager.reset()
        super.tearDown()
    }

    /// Mirrors the shim in LanguageManager.swift exactly.
    private func shimResolved(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: nil,
               bundle: LanguageManager.bundleOverride ?? .main,
               locale: LanguageManager.activeLocale, comment: nil)
    }

    func testLanguageBundlesShipInTheApp() {
        LanguageManager.apply("en")
        XCTAssertNotNil(LanguageManager.bundleOverride,
                        "en.lproj must exist in the app bundle")
        LanguageManager.apply("ro")
        XCTAssertNotNil(LanguageManager.bundleOverride,
                        "ro.lproj must exist in the app bundle")
    }

    func testShimResolvesEnglishWhenEnglishChosen() {
        LanguageManager.apply("en")
        XCTAssertEqual(shimResolved("language_title"), "Language")
        XCTAssertEqual(shimResolved("lang_select_section"), "SELECT LANGUAGE")
    }

    func testShimResolvesRomanianWhenRomanianChosen() {
        LanguageManager.apply("ro")
        XCTAssertEqual(shimResolved("language_title"), "Limbă")
        XCTAssertEqual(shimResolved("lang_select_section"), "SELECTEAZĂ LIMBA")
    }

    func testSwizzledBundleLookupFollowsChosenLanguage() {
        LanguageManager.apply("en")
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "language_title", value: nil, table: nil),
            "Language")
        LanguageManager.apply("ro")
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "language_title", value: nil, table: nil),
            "Limbă")
    }
}
