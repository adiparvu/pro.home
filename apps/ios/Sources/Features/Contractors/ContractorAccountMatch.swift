import Foundation

// MARK: - Contractor ↔ PRVIO account matching

/// Matches a contractor against the property's members — people who already
/// have a PRVIO account on this property — by phone or email. A hit powers
/// the "PRVIO" badge, the in-app DM bridge, and the richer peek card.
///
/// Pure and synchronous by design so it is trivially unit-testable and can
/// run inline during row construction without touching the network.
enum ContractorAccountMatch {

    /// Minimum digits a phone field must contain before it can participate in
    /// matching — short fragments ("112", extension stubs) must never link a
    /// contractor to an account.
    private static let minPhoneDigits = 6

    /// Normalizes a phone number into a comparable key: strips every
    /// non-digit (spaces, dashes, parentheses, "+"), then keeps the last 9
    /// digits so "+40 745 123 456", "0040745123456" and "0745-123-456" all
    /// collapse to the same national significant number.
    /// Returns nil when the field is missing or has too few digits to be safe.
    static func phoneKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        guard digits.count >= minPhoneDigits else { return nil }
        return String(digits.suffix(9))
    }

    /// Normalizes an email into a comparable key: trims whitespace and
    /// lowercases. Returns nil for empty or non-address values so blank
    /// fields can never match each other.
    static func emailKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.contains("@") ? email : nil
    }

    /// The property member matching this contractor, if any. Email is the
    /// stronger identity signal, so it is resolved first across all members
    /// (exact after normalization) before falling back to the phone key.
    /// Contractors and members with neither field never match.
    static func member(for contractor: ContractorModel, in members: [FamilyMember]) -> FamilyMember? {
        if let email = emailKey(contractor.email),
           let hit = members.first(where: { emailKey($0.email) == email }) {
            return hit
        }
        if let phone = phoneKey(contractor.phone),
           let hit = members.first(where: { phoneKey($0.phone) == phone }) {
            return hit
        }
        return nil
    }

    /// Bulk variant for list rendering: indexes the members once (O(m)) and
    /// sweeps the contractors once (O(n)), instead of O(n·m) per render.
    static func matches(contractors: [ContractorModel],
                        members: [FamilyMember]) -> [UUID: FamilyMember] {
        guard !members.isEmpty, !contractors.isEmpty else { return [:] }
        var byEmail: [String: FamilyMember] = [:]
        var byPhone: [String: FamilyMember] = [:]
        for member in members {
            if let key = emailKey(member.email), byEmail[key] == nil { byEmail[key] = member }
            if let key = phoneKey(member.phone), byPhone[key] == nil { byPhone[key] = member }
        }
        var result: [UUID: FamilyMember] = [:]
        for contractor in contractors {
            if let key = emailKey(contractor.email), let member = byEmail[key] {
                result[contractor.id] = member
            } else if let key = phoneKey(contractor.phone), let member = byPhone[key] {
                result[contractor.id] = member
            }
        }
        return result
    }
}
