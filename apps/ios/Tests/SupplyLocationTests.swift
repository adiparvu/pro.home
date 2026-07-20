import XCTest
@testable import PRVIO

// Unit tests for SupplyLocation — canonical item-location slugs. Locations
// are STORED as English slugs ("kitchen"…) and DISPLAYED localized, so a
// household mixing "Kitchen" and "Bucătărie" sees one location, not two.
// Pure logic + bundle localization, no UI or network. Run with Cmd+U
// (PRVIOTests scheme).
final class SupplyLocationTests: XCTestCase {

    // MARK: - normalized (what gets written to storage)

    func testRomanianNameNormalizesToCanonicalSlug() {
        XCTAssertEqual(SupplyLocation.normalized("Bucătărie"), "kitchen")
    }

    func testUnknownLocationStoresRawTrimmed() {
        XCTAssertEqual(SupplyLocation.normalized("  Rocket Hangar  "), "Rocket Hangar")
    }

    func testCaseAndDiacriticsAndWhitespaceAreFolded() {
        XCTAssertEqual(SupplyLocation.normalized("BAIE "), "bathroom")
        XCTAssertEqual(SupplyLocation.normalized("BUCĂTĂRIE"), "kitchen")
        XCTAssertEqual(SupplyLocation.normalized(" gRăDiNă "), "garden")
    }

    func testEmptyAndWhitespaceOnlyInputStaysEmpty() {
        XCTAssertEqual(SupplyLocation.normalized(""), "")
        XCTAssertEqual(SupplyLocation.normalized("   "), "")
    }

    // MARK: - displayName (what gets shown)

    func testDisplayNameForKnownSlugIsLocalized() {
        let name = SupplyLocation.displayName(for: "kitchen")
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, "kitchen",
                          "a known slug must render its localized name, not the raw slug")
        XCTAssertFalse(name.hasPrefix("sup_loc_"),
                       "localization key leaked to the UI — missing xcstrings entry?")
    }

    func testDisplayNameForUnknownValueFallsBackToRaw() {
        XCTAssertEqual(SupplyLocation.displayName(for: "Rocket Hangar"), "Rocket Hangar")
    }

    func testLegacyTextAndSlugDisplayTheSameName() {
        // The whole point of canonicalization: "Bucătărie" and "kitchen"
        // must collapse to ONE displayed location.
        XCTAssertEqual(SupplyLocation.displayName(for: "Bucătărie"),
                       SupplyLocation.displayName(for: "kitchen"))
    }

    // MARK: - Table integrity

    func testEveryKnownSlugResolvesToItself() {
        // Each canonical slug must be its own alias, or a stored slug would
        // stop round-tripping (normalized would return it as "unknown" text
        // and displayName would show the raw slug).
        for entry in SupplyLocation.known {
            XCTAssertEqual(SupplyLocation.canonicalSlug(for: entry.slug), entry.slug,
                           "slug '\(entry.slug)' is missing from the alias table")
        }
    }

    func testEveryKnownSlugHasALocalizedDisplayName() {
        for entry in SupplyLocation.known {
            let name = SupplyLocation.displayName(for: entry.slug)
            XCTAssertFalse(name.isEmpty, "slug '\(entry.slug)' displays empty")
            XCTAssertFalse(name.hasPrefix("sup_loc_"),
                           "slug '\(entry.slug)' leaks its localization key")
        }
    }
}
