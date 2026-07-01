import SwiftUI

struct AddPropertyValueSheet: View {
    @EnvironmentObject private var propertyValueService: PropertyValueService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var currencyService: CurrencyService
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var currency = "EUR"
    @State private var source = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false

    private let currencies = ["EUR", "RON", "USD", "GBP"]
    private let commonSources = ["Manual estimate", "Bank appraisal", "Real estate agent", "Online estimate", "Official valuation"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        formSection("Value") {
                            HStack(spacing: 10) {
                                Image(systemName: "banknote.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                TextField("0", text: $valueText)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                                    .keyboardType(.decimalPad)
                                Spacer()
                                Picker("Currency", selection: $currency) {
                                    ForEach(currencies, id: \.self) { c in
                                        Text(c).tag(c)
                                    }
                                }
                                .tint(.accentColor)
                                .pickerStyle(.menu)
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.base)
                        }

                        formSection("Details") {
                            sourcePicker
                            divider
                            DatePicker(
                                "Date",
                                selection: $date,
                                displayedComponents: .date
                            )
                            .tint(.accentColor)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)
                        }

                        formSection("Notes") {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                    .padding(.top, 2)
                                TextField("Optional notes…", text: $notes, axis: .vertical)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                                    .lineLimit(3...6)
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, 13)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Add Value Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.accentColor)
                    } else {
                        Button("Save") { Task { await save() } }
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .disabled((Double(valueText) ?? 0) <= 0 || isSaving)
                    }
                }
            }
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                TextField("Source (e.g. Bank appraisal)", text: $source)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)

            if source.isEmpty {
                Divider().opacity(0.3).padding(.leading, 52)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(commonSources, id: \.self) { s in
                            Button {
                                source = s
                                HapticFeedback.impact(.light)
                            } label: {
                                Text(LocalizedStringKey(s))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, AppSpacing.xs)
                                    .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                }
            }
        }
    }

    private func formSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func save() async {
        guard let amount = Double(valueText), amount > 0,
              let propertyId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        isSaving = true
        defer { isSaving = false }
        let payload = NewPropertyValuePayload(
            propertyId: propertyId,
            ownerId: ownerId,
            valueAmount: amount,
            currency: currency,
            source: source.isEmpty ? nil : source,
            notes: notes.isEmpty ? nil : notes,
            enteredAt: ISO8601DateFormatter().string(from: date)
        )
        await propertyValueService.add(payload)
        HapticFeedback.success()
        dismiss()
    }
}
