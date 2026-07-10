import SwiftUI

struct AddFinancialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PropertyService.self) private var propertyService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(FamilyService.self) private var familyService

    let onSaved: () async -> Void

    @State private var title = ""
    @State private var amount = ""
    @State private var type = "expense"
    @State private var category = "other"
    @State private var date = Date()
    @State private var notes = ""
    @State private var sharedMemberIds: [String] = []
    @State private var sharedMemberNames: [String] = []
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showError = false
    /// Last category the keyword suggester filled in. The suggester only ever
    /// overwrites its own suggestion (or the untouched default) — the moment
    /// the user picks a category manually, it stops interfering.
    @State private var autoSuggestedCategory: String? = nil

    private let types = ["income", "expense"]

    private var categories: [String] {
        type == "income"
            ? ["salary", "rent", "investment", "other"]
            : ["groceries", "transport", "dining", "shopping", "healthcare",
               "rent", "utilities", "maintenance", "insurance", "taxes",
               "mortgage", "supplies", "other"]
    }

    var body: some View {
        FormScaffold(title: "Add Record",
                     canSave: !title.isEmpty && !amount.isEmpty,
                     isSaving: isSaving,
                     error: Binding(
                         get: { showError ? errorMessage : nil },
                         set: { if $0 == nil { showError = false } }
                     ),
                     onSave: { Task { await save() } }) {
            typeSelector
            amountField
            detailsSection
            notesField
            shareSection
        }
        .task { if familyService.members.isEmpty { await familyService.load() } }
        .onChange(of: title) { _, newTitle in
            guard let suggestion = FinanceCategorySuggester.suggest(from: newTitle),
                  categories.contains(suggestion),
                  category == "other" || category == autoSuggestedCategory
            else { return }
            withAnimation(.snappy) {
                category = suggestion
                autoSuggestedCategory = suggestion
            }
        }
        .onChange(of: type) { _, _ in
            // Income and expense have different category sets; never keep a
            // selection the picker can no longer show.
            if !categories.contains(category) { category = "other" }
        }
    }

    // MARK: - Type selector

    private var typeSelector: some View {
        GlassCard {
            HStack(spacing: 8) {
                ForEach(types, id: \.self) { t in
                    Button {
                        withAnimation(.spring(response: 0.25)) { type = t }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t == "income" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(AppFont.scaled(14))
                            Text(LocalizedStringKey(t.capitalized))
                                .font(AppFont.footnoteEmphasis)
                        }
                        .foregroundStyle(type == t ? Color.black : Color.primary.opacity(AppOpacity.mediumText))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            type == t
                                ? (t == "income" ? Color.brandSuccess : Color.red)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Amount

    private var amountField: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("AMOUNT")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))

                HStack(alignment: .center, spacing: 8) {
                    Text(currencyService.symbol(for: appSettings.preferredCurrency))
                        .font(AppFont.scaled(32, weight: .light))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    TextField("0", text: $amount)
                        .font(AppFont.scaled(40, weight: .light))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        FormGroup {
            // Title
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "tag.fill", color: .blue)
                TextField("Title", text: $title)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)

            divider

            // Category
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "folder.fill", color: .purple)
                Text("Category")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                if category != "other", category == autoSuggestedCategory {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.yellow)
                        .transition(.opacity.combined(with: .scale))
                        .accessibilityLabel(Text("fin_category_suggested"))
                }
                Spacer()
                Picker("", selection: $category) {
                    ForEach(categories, id: \.self) { cat in
                        Text(LocalizedStringKey(cat.capitalized)).tag(cat)
                    }
                }
                .tint(Color.primary.opacity(AppOpacity.mediumText))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.xs)

            divider

            // Date
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "calendar", color: .orange)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.xs)
        }
    }

    // MARK: - Notes

    private var notesField: some View {
        FormGroup {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "note.text", color: .cyan)
                TextField("Notes (optional)", text: $notes)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Share with

    // Finances are visible to household adults by default. Sharing a specific
    // record surfaces it to a scoped member (e.g. a tenant's own utility bill)
    // without granting them the rest of the ledger. Writes family_members.id
    // strings into shared_member_ids (RLS: is_shared_with_me, migration 094).
    @ViewBuilder
    private var shareSection: some View {
        if !familyService.members.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Share with")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Spacer()
                    if !sharedMemberIds.isEmpty {
                        Text("\(sharedMemberIds.count)")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                }
                Text("Only household adults see finances. Anyone you add here can see this one record.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                MemberPickerView(selectedIds: $sharedMemberIds, selectedNames: $sharedMemberNames)
            }
            .padding(AppSpacing.base)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5)
            )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    // MARK: - Save

    private func save() async {
        guard let amountDouble = Double(amount.replacingOccurrences(of: ",", with: ".")),
              let propertyId = propertyService.primary?.id else {
            errorMessage = propertyService.primary == nil
                ? String(localized: "No property found.")
                : String(localized: "Invalid amount.")
            showError = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        let dateString = AppDate.dayString(from: date)
        let now = ISO8601DateFormatter().string(from: Date())

        struct NewRecord: Encodable {
            let propertyId: UUID
            let title: String
            let amount: Double
            let currency: String
            let type: String
            let category: String
            let date: String
            let description: String?
            let createdAt: String
            let sharedMemberIds: [String]
            enum CodingKeys: String, CodingKey {
                case title, amount, currency, type, category, date, description
                case propertyId = "property_id"
                case createdAt = "created_at"
                case sharedMemberIds = "shared_member_ids"
            }
        }

        do {
            try await supabase
                .from("financial_records")
                .insert(NewRecord(
                    propertyId: propertyId,
                    title: title,
                    amount: amountDouble,
                    currency: appSettings.preferredCurrency,
                    type: type,
                    category: category,
                    date: dateString,
                    description: notes.isEmpty ? nil : notes,
                    createdAt: now,
                    sharedMemberIds: sharedMemberIds
                ))
                .execute()

            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Category suggestion (local RO/EN keyword dictionary)
//
// A tiny on-device merchant/keyword table that pre-fills the category from
// the title as it is typed. It is only ever a suggestion: it fills the
// picker, never locks it, and stops overriding once the user picks manually.
// No network, no fabrication — an unknown title simply suggests nothing.

enum FinanceCategorySuggester {
    /// Ordered: specific merchant names before generic words, so "taxi"
    /// resolves to transport before "taxa" reaches taxes.
    private static let rules: [(keywords: [String], category: String)] = [
        (["kaufland", "lidl", "carrefour", "auchan", "penny", "profi",
          "mega image", "megaimage", "aldi", "selgros", "supermarket",
          "alimente", "cumparaturi", "cumpărături", "groceries", "grocery",
          "piata", "piața", "piată"], "groceries"),
        // Before transport, so "Bolt Food" reaches dining and not "bolt".
        (["restaurant", "pizza", "pizzerie", "shaorma", "kfc", "mcdonald",
          "glovo", "tazz", "foodpanda", "bolt food", "cafenea", "cafea",
          "coffee", "starbucks", "5togo"], "dining"),
        (["omv", "petrom", "rompetrol", "lukoil", "mol", "socar",
          "benzina", "benzină", "benzinarie", "benzinărie", "motorina",
          "motorină", "carburant", "combustibil", "fuel", "uber", "bolt",
          "taxi", "metrorex", "stb", "ratb", "cfr", "parcare", "parking",
          "rovinieta", "rovinietă", "transport"], "transport"),
        (["enel", "engie", "eon", "e.on", "ppc", "hidroelectrica", "electrica",
          "digi", "rcs", "rds", "orange", "vodafone", "telekom", "yoxo",
          "apa nova", "salubritate", "curent", "curentul", "gaze", "internet",
          "utilities", "electricity", "intretinere", "întreținere"], "utilities"),
        (["chirie", "chiria", "chiriei", "rent"], "rent"),
        (["asigurare", "asigurarea", "rca", "casco", "allianz", "groupama",
          "omniasig", "generali", "asirom", "insurance"], "insurance"),
        (["impozit", "impozite", "impozitul", "anaf", "taxa", "taxă", "taxe",
          "tax"], "taxes"),
        (["ipoteca", "ipotecă", "ipotecar", "rata credit", "rată credit",
          "rata banca", "mortgage", "prima casa", "noua casa"], "mortgage"),
        (["emag", "altex", "flanco", "zara", "h&m", "decathlon", "epantofi",
          "fashion days", "mall", "shopping"], "shopping"),
        (["dedeman", "leroy merlin", "hornbach", "brico", "ikea", "jysk",
          "consumabile", "supplies"], "supplies"),
        (["farmacie", "farmacia", "catena", "sensiblu", "helpnet", "dr.max",
          "medic", "medicul", "clinica", "clinică", "dentist", "stomatolog",
          "spital", "regina maria", "medlife", "sanador", "pharmacy",
          "doctor"], "healthcare"),
        (["reparatie", "reparație", "reparatii", "reparații", "instalator",
          "electrician", "zugrav", "mentenanta", "mentenanță", "service",
          "revizie", "repair", "maintenance"], "maintenance"),
        (["salariu", "salariul", "salary", "payroll", "wage", "bonus"], "salary"),
        (["dividende", "dividend", "dobanda", "dobândă", "interest",
          "investitie", "investiție", "investment", "actiuni", "acțiuni"], "investment"),
    ]

    /// The category the title's words point at, or nil. Matching is
    /// word-based: short keywords ("mol", "rca", "stb") must equal a whole
    /// word so they never fire inside unrelated words; longer ones match as
    /// word prefixes ("impozitul", "chiria"); multi-word phrases as substrings.
    static func suggest(from text: String) -> String? {
        let lower = text.lowercased()
        guard lower.count >= 3 else { return nil }
        let words = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "&" && $0 != "." })
            .map(String.init)
        for rule in rules {
            for keyword in rule.keywords {
                let hit: Bool
                if keyword.contains(" ") {
                    hit = lower.contains(keyword)
                } else if keyword.count <= 4 {
                    hit = words.contains(keyword)
                } else {
                    hit = words.contains { $0.hasPrefix(keyword) }
                }
                if hit { return rule.category }
            }
        }
        return nil
    }
}
