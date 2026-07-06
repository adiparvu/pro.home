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

    private let types = ["income", "expense"]
    private let categories = ["rent", "utilities", "maintenance", "insurance", "taxes", "mortgage", "supplies", "other"]

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
                                .font(.system(size: 14))
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
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    TextField("0", text: $amount)
                        .font(.system(size: 40, weight: .light))
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
                    .font(.system(size: 15))
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
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
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
                    .font(.system(size: 15))
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
                    .font(.system(size: 15))
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

        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        let dateString = iso.string(from: date)
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
