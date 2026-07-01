import XCTest
@testable import PRVIO

// Unit tests for pure model logic on SocialLink and FamilyMember — platform
// mapping, social handle → URL construction (with sanitization), and initials
// derivation. No UI or network. Run with Cmd+U (PRVIOTests scheme).
final class FamilyModelTests: XCTestCase {

    private func link(_ platform: String, _ handle: String) -> SocialLink {
        SocialLink(platform: platform, handle: handle)
    }

    private func member(name: String) -> FamilyMember {
        FamilyMember(id: UUID(), ownerId: UUID(), propertyId: nil, name: name,
                     email: nil, phone: nil, role: "child", avatarUrl: nil,
                     color: "#3B82F6", birthday: nil, socialLinks: nil,
                     createdAt: "2026-01-01T00:00:00Z")
    }

    // MARK: - SocialLink.platformLabel

    func testPlatformLabelKnown() {
        XCTAssertEqual(link("instagram", "x").platformLabel, "Instagram")
        XCTAssertEqual(link("twitter", "x").platformLabel, "X (Twitter)")
        XCTAssertEqual(link("whatsapp", "x").platformLabel, "WhatsApp")
    }

    func testPlatformLabelUnknownCapitalizes() {
        XCTAssertEqual(link("myspace", "x").platformLabel, "Myspace")
    }

    // MARK: - SocialLink.platformIcon

    func testPlatformIconKnownAndFallback() {
        XCTAssertEqual(link("instagram", "x").platformIcon, "camera.filters")
        XCTAssertEqual(link("telegram", "x").platformIcon, "paperplane.fill")
        XCTAssertEqual(link("myspace", "x").platformIcon, "link")
    }

    // MARK: - SocialLink.openURL

    func testOpenURLStripsAtSymbol() {
        XCTAssertEqual(link("instagram", "@john").openURL?.absoluteString,
                       "https://instagram.com/john")
        XCTAssertEqual(link("tiktok", "@dancer").openURL?.absoluteString,
                       "https://tiktok.com/@dancer")
    }

    func testOpenURLTrimsWhitespace() {
        XCTAssertEqual(link("twitter", "  jack  ").openURL?.absoluteString,
                       "https://x.com/jack")
    }

    func testOpenURLWhatsAppKeepsOnlyDigits() {
        XCTAssertEqual(link("whatsapp", "+40 712 345 678").openURL?.absoluteString,
                       "https://wa.me/40712345678")
    }

    func testOpenURLUnknownPlatformUsesRawHandle() {
        XCTAssertEqual(link("custom", "https://example.com/me").openURL?.absoluteString,
                       "https://example.com/me")
    }

    // MARK: - FamilyMember.initials

    func testInitialsTwoWords() {
        XCTAssertEqual(member(name: "Ion Popescu").initials, "IP")
    }

    func testInitialsThreeWordsUsesFirstTwo() {
        XCTAssertEqual(member(name: "Maria Elena Ionescu").initials, "ME")
    }

    func testInitialsSingleWordUsesFirstTwoChars() {
        XCTAssertEqual(member(name: "Ana").initials, "AN")
    }

    func testInitialsSingleCharacter() {
        XCTAssertEqual(member(name: "X").initials, "X")
    }

    func testInitialsCollapsesExtraSpaces() {
        // split(separator:) omits empty subsequences, so leading/among spaces
        // still yield the first two words' initials.
        XCTAssertEqual(member(name: "  Ion   Popescu").initials, "IP")
    }
}
