import XCTest
@testable import PRVIO

// The icon picker browses families; every catalog theme must belong to
// exactly one. A theme missing from the family map would silently vanish
// from the gallery — this pins the two lists together.
final class AppIconFamilyTests: XCTestCase {

    func testEveryThemeBelongsToExactlyOneFamily() {
        let catalogIDs = AppIconCatalog.all.map(\.id)
        let familyIDs = AppIconFamilies.all.flatMap(\.variantIDs)

        XCTAssertEqual(familyIDs.count, Set(familyIDs).count,
                       "A theme appears in more than one family")
        XCTAssertEqual(Set(familyIDs), Set(catalogIDs),
                       "Family map and catalog diverge")
    }

    func testFamilyVariantsResolve() {
        for family in AppIconFamilies.all {
            XCTAssertFalse(family.variants.isEmpty)
            for (id, theme) in zip(family.variantIDs, family.variants) {
                XCTAssertEqual(theme.id, id, "Variant \(id) resolved to \(theme.id)")
            }
        }
    }

    func testFamilyLookupFindsEveryTheme() {
        for theme in AppIconCatalog.all {
            XCTAssertTrue(AppIconFamilies.family(containing: theme.id)
                .variantIDs.contains(theme.id))
        }
    }
}
