import SwiftUI

// MARK: - SupplyLocation — canonical item locations
//
// Item locations are STORED as canonical English slugs ("kitchen",
// "pantry"…) and DISPLAYED through localization, so a household mixing
// "Kitchen" and "Bucătărie" sees one location, not two. Legacy free-text
// values (Romanian or any supported language) map onto the canonical slug
// at read time; anything unknown is shown exactly as the user typed it —
// never guessed, never hidden.
enum SupplyLocation {

    /// Canonical slug → localization key. The single source of truth for
    /// which locations the module knows about.
    static let known: [(slug: String, key: String.LocalizationValue)] = [
        ("kitchen",  "sup_loc_kitchen"),
        ("pantry",   "sup_loc_pantry"),
        ("bathroom", "sup_loc_bathroom"),
        ("bedroom",  "sup_loc_bedroom"),
        ("living",   "sup_loc_living"),
        ("garage",   "sup_loc_garage"),
        ("garden",   "sup_loc_garden"),
        ("balcony",  "sup_loc_balcony"),
        ("basement", "sup_loc_basement"),
        ("attic",    "sup_loc_attic"),
        ("hallway",  "sup_loc_hallway"),
        ("office",   "sup_loc_office"),
        ("laundry",  "sup_loc_laundry"),
        ("storage",  "sup_loc_storage"),
    ]

    /// Folded alias → canonical slug. Covers the app's languages (RO, EN,
    /// DE, FR, NL) plus the slugs themselves, so both freshly typed names
    /// and legacy stored values resolve.
    private static let aliases: [String: String] = [
        // kitchen
        "kitchen": "kitchen", "bucatarie": "kitchen", "kuche": "kitchen",
        "cuisine": "kitchen", "keuken": "kitchen",
        // pantry
        "pantry": "pantry", "camara": "pantry", "vorratskammer": "pantry",
        "garde-manger": "pantry", "voorraadkast": "pantry",
        // bathroom
        "bathroom": "bathroom", "baie": "bathroom", "badezimmer": "bathroom",
        "bad": "bathroom", "salle de bain": "bathroom", "badkamer": "bathroom",
        // bedroom
        "bedroom": "bedroom", "dormitor": "bedroom", "schlafzimmer": "bedroom",
        "chambre": "bedroom", "slaapkamer": "bedroom",
        // living room
        "living": "living", "living room": "living", "sufragerie": "living",
        "camera de zi": "living", "wohnzimmer": "living", "salon": "living",
        "woonkamer": "living",
        // garage
        "garage": "garage", "garaj": "garage",
        // garden
        "garden": "garden", "gradina": "garden", "garten": "garden",
        "jardin": "garden", "tuin": "garden",
        // balcony
        "balcony": "balcony", "balcon": "balcony", "balkon": "balcony",
        // basement
        "basement": "basement", "subsol": "basement", "keller": "basement",
        "sous-sol": "basement", "kelder": "basement", "beci": "basement",
        // attic
        "attic": "attic", "pod": "attic", "mansarda": "attic",
        "dachboden": "attic", "grenier": "attic", "zolder": "attic",
        // hallway
        "hallway": "hallway", "hol": "hallway", "flur": "hallway",
        "couloir": "hallway", "gang": "hallway", "hal": "hallway",
        // office
        "office": "office", "birou": "office", "buro": "office",
        "bureau": "office", "kantoor": "office",
        // laundry
        "laundry": "laundry", "spalatorie": "laundry", "waschkuche": "laundry",
        "buanderie": "laundry", "wasruimte": "laundry",
        // storage
        "storage": "storage", "depozit": "storage", "depozitare": "storage",
        "debara": "storage", "abstellraum": "storage", "rangement": "storage",
        "berging": "storage",
    ]

    /// The canonical slug for any typed/stored location, if it is known.
    static func canonicalSlug(for raw: String) -> String? {
        let folded = ReceiptProductLexicon.fold(raw)
        guard !folded.isEmpty else { return nil }
        return aliases[folded]
    }

    /// What gets written to storage: the canonical slug when the value is
    /// recognized, otherwise the user's text, trimmed and untouched.
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return canonicalSlug(for: trimmed) ?? trimmed
    }

    /// What gets shown: the localized name when the stored value maps to a
    /// canonical location (slug or legacy text alike); the raw value
    /// otherwise — honest about what we don't recognize.
    static func displayName(for stored: String) -> String {
        guard let slug = canonicalSlug(for: stored),
              let key = known.first(where: { $0.slug == slug })?.key
        else { return stored }
        return String(localized: key)
    }
}

// MARK: - QuantityBadge — the module's one quantity treatment
//
// A neutral capsule everywhere a quantity appears; the accent turns on
// only for the pantry's existing low-stock concept — never decorative.
struct QuantityBadge: View {
    let text: String
    var isLow: Bool = false

    var body: some View {
        Text(verbatim: text)
            .font(AppFont.label)
            .monospacedDigit()
            .foregroundStyle(isLow ? Color.brandDanger : .secondary)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 2)
            .background(isLow ? Color.brandDanger.opacity(0.12)
                              : Color.primary.opacity(AppOpacity.subtleFill),
                        in: Capsule())
            .contentTransition(.numericText())
    }
}
