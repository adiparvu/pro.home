import XCTest
import UIKit
@testable import PRVIO

// Tests for the app's single-source authorities introduced by the
// foundation-hardening pass: AppDate (calendar dates), CurrencyService.money
// (money display), SignedStorage (documents-bucket URL handling),
// PropertyRole (role gating) and the upload image pipeline.
//
// Assertions are deliberately structural (round-trips, invariants) rather
// than exact strings wherever the output is locale- or timezone-dependent,
// so they stay deterministic on any CI machine.

final class AppDateTests: XCTestCase {
    func testDayRoundTrip() {
        let s = "2026-07-06"
        guard let d = AppDate.day(from: s) else { return XCTFail("parse failed") }
        XCTAssertEqual(AppDate.dayString(from: d), s)
    }

    func testDayTimeParses() {
        XCTAssertNotNil(AppDate.day(from: "2026-07-06 14:30"))
    }

    func testDayFallsBackToDatePortionOfTimestamps() {
        guard let d = AppDate.day(from: "2026-07-06T10:00:00+00:00") else {
            return XCTFail("timestamp day parse failed")
        }
        // Whatever the timezone, the parsed instant must map back to a
        // valid wire day string.
        XCTAssertEqual(AppDate.dayString(from: d).count, 10)
    }

    func testTimestampToleratesEveryPostgresShape() {
        // Plain Z, explicit offset, microsecond fractions, offset-less.
        let shapes = [
            "2026-07-06T10:00:00Z",
            "2026-07-06T10:00:00+00:00",
            "2026-07-06T10:00:00.123456+00:00",
            "2026-07-06T10:00:00.5+02:00",
            "2026-07-06T10:00:00",
        ]
        for s in shapes {
            XCTAssertNotNil(AppDate.timestamp(from: s), "failed to parse \(s)")
        }
    }

    func testMicrosecondFractionMatchesMillisecondTruncation() {
        let micro = AppDate.timestamp(from: "2026-07-06T10:00:00.123456Z")
        let milli = AppDate.timestamp(from: "2026-07-06T10:00:00.123Z")
        XCTAssertNotNil(micro)
        XCTAssertEqual(micro, milli)
    }

    func testGarbageStaysNil() {
        XCTAssertNil(AppDate.day(from: "not a date"))
        XCTAssertNil(AppDate.timestamp(from: "yesterday"))
    }
}

final class MoneyTests: XCTestCase {
    func testWholeRoundsInsteadOfTruncating() {
        // Int() truncation showed 99; the authority must round to 100.
        let s = CurrencyService.money(99.9, code: "EUR", whole: true)
        XCTAssertTrue(s.contains("100"), "expected rounding, got \(s)")
        XCTAssertFalse(s.contains("99"), "truncation artifact in \(s)")
    }

    func testCentsAppearOnlyWhenPresent() {
        let whole = CurrencyService.money(50, code: "EUR")
        let cents = CurrencyService.money(50.25, code: "EUR")
        XCTAssertTrue(whole.contains("50"))
        XCTAssertTrue(cents.contains("25"), "cents dropped from \(cents)")
    }

    func testSupportedSymbols() {
        XCTAssertEqual(CurrencyService.symbol(for: "RON"), "lei")
        XCTAssertEqual(CurrencyService.symbol(for: "EUR"), "€")
        XCTAssertEqual(CurrencyService.symbol(for: "XYZ"), "XYZ")
    }
}

final class SignedStorageTests: XCTestCase {
    func testExtractsDocumentsPathFromPublicURL() {
        let url = "https://kwcanenheihuylaymwsl.supabase.co/storage/v1/object/public/documents/uid/avatars/a.jpg"
        XCTAssertEqual(SignedStorage.documentsPath(from: url), "uid/avatars/a.jpg")
    }

    func testDecodesPercentEncodedPaths() {
        let url = "https://x.supabase.co/storage/v1/object/public/documents/uid/My%20File.pdf"
        XCTAssertEqual(SignedStorage.documentsPath(from: url), "uid/My File.pdf")
    }

    func testPassesThroughForeignAndSignedURLs() {
        XCTAssertNil(SignedStorage.documentsPath(from: "https://example.com/cat.jpg"))
        XCTAssertNil(SignedStorage.documentsPath(from: "https://x.supabase.co/storage/v1/object/sign/documents/a.jpg?token=t"))
        XCTAssertNil(SignedStorage.documentsPath(from: "https://x.supabase.co/storage/v1/object/public/chat-media/a.jpg"))
        XCTAssertNil(SignedStorage.documentsPath(from: ""))
    }
}

final class PropertyRoleTests: XCTestCase {
    func testNilMeansStillLoading() {
        XCTAssertNil(PropertyRole.resolve(nil))
    }

    func testUnknownStringsFailClosedToGuest() {
        XCTAssertEqual(PropertyRole.resolve("adult"), .guest)      // the old bug
        XCTAssertEqual(PropertyRole.resolve("superadmin"), .guest)
        XCTAssertEqual(PropertyRole.resolve(""), .guest)
    }

    func testEveryDatabaseRoleResolves() {
        for role in PropertyRole.allCases {
            XCTAssertEqual(PropertyRole.resolve(role.rawValue), role)
        }
    }

    func testOnlyLandlordClassManagesMembers() {
        XCTAssertTrue(PropertyRole.owner.canManageMembers)
        XCTAssertTrue(PropertyRole.partner.canManageMembers)
        for role in PropertyRole.allCases where role != .owner && role != .partner {
            XCTAssertFalse(role.canManageMembers, "\(role) must not manage members")
        }
    }
}

final class ImagePipelineTests: XCTestCase {
    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        // scale = 1 so the point sizes below ARE the pixel sizes — the
        // simulator's default 3x scale would silently triple them.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testOversizedImagesAreCapped() throws {
        let big = solidImage(width: 4000, height: 3000)
        let data = try XCTUnwrap(big.uploadJPEG(quality: 0.8, maxDimension: 2560))
        let decoded = try XCTUnwrap(UIImage(data: data))
        let longest = max(decoded.size.width, decoded.size.height) * decoded.scale
        XCTAssertLessThanOrEqual(longest, 2560 + 1)
    }

    func testSmallImagesPassThroughUnscaled() throws {
        let small = solidImage(width: 800, height: 600)
        let data = try XCTUnwrap(small.uploadJPEG(quality: 0.8, maxDimension: 2560))
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(decoded.size.width, decoded.size.height) * decoded.scale, 800, accuracy: 2)
    }
}
