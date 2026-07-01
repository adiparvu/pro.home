import SwiftUI

struct AddFinancialView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings

    let onSaved: () async -> Void

    @State private var title = ""
    @State private var amount = ""
    @State private var type = "expense"
    @State private var category = "other"
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showError = false

    private let types = ["income", "expense"]
    private let categories = ["rent", "utilities", "maintenance", "insurance", "taxes", "mortgage", "supplies", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        typeSelector
                        amountField
                        detailsSection
                        notesField
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save")
                                .font(AppFont.subheadline)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .disabled(isSaving || title.isEmpty || amount.isEmpty)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(LocalizedStringKey(errorMessage))
            }
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
                                .font(.system(size: 14))
                            Text(LocalizedStringKey(t.capitalized))
                                .font(AppFont.footnoteEmphasis)
                        }
                        .foregroundStyle(type == t ? Color.black : Color.primary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            type == t
                                ? (t == "income" ? Color(red: 0.3, green: 0.85, blue: 0.5) : Color.red)
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
                    .foregroundStyle(Color.primary.opacity(0.35))

                HStack(alignment: .center, spacing: 8) {
                    Text(currencyService.symbol(for: appSettings.preferredCurrency))
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.5))
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
        VStack(spacing: 0) {
            // Title
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "tag.fill", color: .blue)
                TextField("Title", text: $title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

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
                .tint(Color.primary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            divider

            // Date
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "calendar", color: .orange)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - Notes

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "note.text", color: .cyan)
                TextField("Notes (optional)", text: $notes)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
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
            errorMessage = propertyService.primary == nil ? "No property found." : "Invalid amount."
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
            enum CodingKeys: String, CodingKey {
                case title, amount, currency, type, category, date, description
                case propertyId = "property_id"
                case createdAt = "created_at"
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
                    createdAt: now
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
