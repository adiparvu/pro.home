import XCTest
@testable import PRVIO

// Unit tests for ContractorAccountMatch — the pure phone/email normalization
// that links a contractor to a property member with a PRVIO account. No UI or
// network. Run with Cmd+U (PRVIOTests scheme).
final class ContractorAccountMatchTests: XCTestCase {

    // MARK: - Fixtures

    private func contractor(phone: String? = nil, email: String? = nil) -> ContractorModel {
        ContractorModel(id: UUID(), name: "Ion Instalatorul", category: "plumber",
                        phone: phone, email: email, notes: nil, rating: nil,
                        isPreferred: false, website: nil, address: nil)
    }

    private func member(name: String = "Ion Pop",
                        phone: String? = nil,
                        email: String? = nil) -> FamilyMember {
        FamilyMember(id: UUID(), ownerId: UUID(), propertyId: nil, name: name,
                     email: email, phone: phone, role: "guest", avatarUrl: nil,
                     color: "#3B82F6", birthday: nil, socialLinks: nil,
                     createdAt: "2026-01-01T00:00:00Z")
    }

    // MARK: - Phone matching (prefix + formatting tolerance)

    func testPhoneMatchesAcrossPlus40AndZeroPrefix() {
        let m = member(phone: "+40 745 123 456")
        let c = contractor(phone: "0745-123-456")
        XCTAssertEqual(ContractorAccountMatch.member(for: c, in: [m])?.id, m.id)
    }

    func testPhoneMatchesAcross0040AndParenthesizedFormat() {
        let m = member(phone: "0040745123456")
        let c = contractor(phone: "(0745) 123 456")
        XCTAssertEqual(ContractorAccountMatch.member(for: c, in: [m])?.id, m.id)
    }

    func testDifferentPhonesDoNotMatch() {
        let m = member(phone: "+40745123456")
        XCTAssertNil(ContractorAccountMatch.member(for: contractor(phone: "0745123457"), in: [m]))
    }

    func testShortPhoneFragmentsNeverMatch() {
        // Fewer than 6 digits is not a usable key on either side.
        let m = member(phone: "12345")
        XCTAssertNil(ContractorAccountMatch.member(for: contractor(phone: "12345"), in: [m]))
    }

    // MARK: - Email matching (case / whitespace tolerance)

    func testEmailMatchesCaseInsensitivelyAndTrimmed() {
        let m = member(email: " Ion.Pop@Example.COM ")
        let c = contractor(email: "ion.pop@example.com")
        XCTAssertEqual(ContractorAccountMatch.member(for: c, in: [m])?.id, m.id)
    }

    func testEmailWithoutAtSignIsIgnored() {
        let m = member(email: "not-an-email")
        XCTAssertNil(ContractorAccountMatch.member(for: contractor(email: "not-an-email"), in: [m]))
    }

    // MARK: - No false positives on empty/nil fields

    func testNilAndEmptyFieldsNeverMatch() {
        let emptyMember = member(phone: "", email: "")
        let nilMember = member()
        // Contractor with no data matches nobody.
        XCTAssertNil(ContractorAccountMatch.member(for: contractor(), in: [emptyMember, nilMember]))
        // Contractor with empty strings matches nobody (empty != empty).
        XCTAssertNil(ContractorAccountMatch.member(for: contractor(phone: "", email: ""),
                                                   in: [emptyMember, nilMember]))
        // Contractor with real data must not match members without any.
        XCTAssertNil(ContractorAccountMatch.member(for: contractor(phone: "0745123456", email: "a@b.co"),
                                                   in: [emptyMember, nilMember]))
    }

    func testEmailWinsOverPhoneWhenBothPresent() {
        let byEmail = member(name: "Email Match", email: "ion@x.ro", phone: "0711111111")
        let byPhone = member(name: "Phone Match", phone: "0745123456")
        let c = contractor(phone: "+40745123456", email: "ION@x.ro")
        XCTAssertEqual(ContractorAccountMatch.member(for: c, in: [byPhone, byEmail])?.id, byEmail.id)
    }

    // MARK: - Bulk index parity

    func testBulkMatchesAgreesWithSingleLookup() {
        let members = [member(phone: "+40 745 123 456"), member(email: "ana@x.ro")]
        let contractors = [contractor(phone: "0745123456"),
                           contractor(email: "ANA@x.ro"),
                           contractor(phone: "0299999999")]
        let bulk = ContractorAccountMatch.matches(contractors: contractors, members: members)
        for c in contractors {
            XCTAssertEqual(bulk[c.id]?.id,
                           ContractorAccountMatch.member(for: c, in: members)?.id)
        }
        XCTAssertEqual(bulk.count, 2)
    }
}
