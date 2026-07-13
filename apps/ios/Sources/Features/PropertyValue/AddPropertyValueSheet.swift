import SwiftUI

// MARK: - Add value entry ("Adaugă valoare")
//
// Rebuilt on FormKit. Three honesty upgrades over the old sheet:
//   • the amount regroups live through the locale's separators as you type
//     (the same table `CurrencyService` displays with), so what you read is
//     exactly what is saved;
//   • the currency defaults from Settings instead of a hardcoded EUR;
//   • the source is a TYPED single choice (manual / bank / agent / other)
//     stored as a stable raw token — never again a hardcoded English string
//     in the database. "Other" opens an optional free-text field whose words
//     are stored (and later displayed) verbatim.
//
// Linking the entry to an evaluation-report document is deliberately absent:
// `property_value_entries` has no document column and `document_links` has no
// value-entry target kind — a dead picker would violate the honesty law.

struct AddPropertyValueSheet: View {
    /// The property the entry belongs to; nil → the active property.
    var propertyId: UUID? = nil

    @Environment(PropertyValueService.self) private var propertyValueService
    @Environment(PropertyService.self) private var propertyService
    // Optional on purpose: the sheet keeps working (with the EUR fallback)
    // if a future presentation site lacks the settings object.
    @Environment(AppSettings.self) private var appSettings: AppSettings?
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var currency = "EUR"
    @State private var source: PropertyValueSource = .manual
    @State private var otherSource = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    /// The chips offered here. `.purchase` is excluded on purpose — the
    /// purchase price is seeded once by the property form, not re-entered.
    private static let choices: [PropertyValueSource] = [.manual, .bank, .agent, .other]

    private var amount: Double? { MoneyInputFormat.value(from: amountText) }

    var body: some View {
        FormScaffold(title: "Add Value Entry",
                     canSave: (amount ?? 0) > 0,
                     isSaving: isSaving,
                     error: $error,
                     onSave: { Task { await save() } }) {
            FormGroup(title: "Value") {
                HStack(spacing: 10) {
                    Image(systemName: "banknote.fill")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    TextField("0", text: $amountText)
                        .font(AppFont.scaled(22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .keyboardType(.decimalPad)
                        .onChange(of: amountText) { _, newValue in
                            let formatted = MoneyInputFormat.normalize(newValue)
                            if formatted != newValue { amountText = formatted }
                        }
                    Spacer()
                    Picker("Currency", selection: $currency) {
                        ForEach(CurrencyService.supported, id: \.code) { c in
                            Text(verbatim: c.code).tag(c.code)
                        }
                    }
                    .tint(.accentColor)
                    .pickerStyle(.menu)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.base)
            }

            FormGroup(title: "prop_value_source_title") {
                sourceChips
                if source == .other {
                    FormDivider()
                    FormRow(icon: "tag") {
                        TextField(String(localized: "prop_value_other_placeholder"),
                                  text: $otherSource)
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.primary)
                            .tint(.accentColor)
                    }
                }
                FormDivider()
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .tint(.accentColor)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
            }

            FormGroup(title: "Notes") {
                FormRow(icon: "note.text") {
                    TextField(String(localized: "Optional notes…"), text: $notes, axis: .vertical)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(3...6)
                }
            }
        }
        .onAppear {
            if let preferred = appSettings?.preferredCurrency,
               CurrencyService.supported.contains(where: { $0.code == preferred }) {
                currency = preferred
            }
        }
    }

    // MARK: Source (typed single choice)

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(Self.choices) { choice in
                    GlassFilterChip(label: choice.displayName,
                                    systemImage: choice.icon,
                                    isSelected: source == choice) {
                        withAnimation(.smooth(duration: 0.25)) { source = choice }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: Save

    private func save() async {
        guard let amount, amount > 0,
              let pid = propertyId ?? propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedOther = otherSource.trimmingCharacters(in: .whitespacesAndNewlines)
        // "Other" with words keeps the user's words (displayed verbatim);
        // every typed choice stores its stable language-independent token.
        let sourceValue = (source == .other && !trimmedOther.isEmpty)
            ? trimmedOther
            : source.rawValue

        // A stale service error must not be mistaken for this save's outcome.
        propertyValueService.error = nil
        await propertyValueService.add(NewPropertyValuePayload(
            propertyId: pid,
            ownerId: ownerId,
            valueAmount: amount,
            currency: currency,
            source: sourceValue,
            notes: notes.isEmpty ? nil : notes,
            enteredAt: ISO8601DateFormatter().string(from: date)
        ))
        if let message = propertyValueService.error {
            propertyValueService.error = nil
            error = message
            HapticFeedback.warning()
            return
        }
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - Live money-input formatting
//
// The input-side companion of `CurrencyService` (the display authority):
// digits regroup as you type ("12345" → "12.345" on a Romanian device,
// "12,345" on an English one), the locale's decimal separator is honored
// with up to two decimals, and parsing strips exactly what formatting
// inserted — the field and the saved Double can never disagree.
enum MoneyInputFormat {
    private static var decimalSeparator: String { Locale.current.decimalSeparator ?? "," }
    private static var groupingSeparator: String { Locale.current.groupingSeparator ?? "." }

    /// Canonicalizes raw field text: strips our own grouping separators,
    /// accepts either "." or "," as the decimal mark (hardware keyboards,
    /// pasted text), caps the fraction at two digits and regroups the
    /// integer part. Idempotent — normalized text normalizes to itself.
    static func normalize(_ raw: String) -> String {
        let ds = decimalSeparator
        // Order matters: grouping separators are ours, remove them first;
        // whatever mark remains was typed as a decimal separator.
        var cleaned = raw.replacingOccurrences(of: groupingSeparator, with: "")
        let alternate = ds == "," ? "." : ","
        cleaned = cleaned.replacingOccurrences(of: alternate, with: ds)

        var parts = cleaned.components(separatedBy: ds)
        let integerDigits = String(parts.removeFirst().filter(\.isNumber).prefix(12))
        let fractionDigits = String(parts.joined().filter(\.isNumber).prefix(2))
        let hasSeparator = cleaned.contains(ds)
        guard !integerDigits.isEmpty || hasSeparator else { return "" }

        let regrouped = grouped(integerDigits)
        return hasSeparator ? regrouped + ds + fractionDigits : regrouped
    }

    /// The Double a normalized field holds, nil while empty/invalid.
    static func value(from text: String) -> Double? {
        let canonical = text
            .replacingOccurrences(of: groupingSeparator, with: "")
            .replacingOccurrences(of: decimalSeparator, with: ".")
        return Double(canonical)
    }

    private static func grouped(_ digits: String) -> String {
        guard !digits.isEmpty, let value = Decimal(string: digits) else { return digits }
        return value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }
}
