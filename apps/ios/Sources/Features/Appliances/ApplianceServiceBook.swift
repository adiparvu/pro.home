import SwiftUI

// MARK: - Appliance service book
//
// Every repair is a REAL expense: interventions are financial_records tagged
// ["service", "appliance:<id>"], so they appear in Finances too and no new
// table was needed. The book shows the history, the total cost of ownership
// (purchase + repairs), and the honest signal every household needs: when
// repairs pass half the purchase price, replacement deserves a thought.

enum ApplianceServiceLog {
    static let serviceTag = "service"

    static func tag(for applianceId: UUID) -> String {
        "appliance:\(applianceId.uuidString)"
    }

    static func interventions(in records: [FinancialRecord], appliance: Appliance) -> [FinancialRecord] {
        records
            .filter { $0.tags.contains(tag(for: appliance.id)) }
            .sorted { $0.date > $1.date }
    }

    static func totalRepairs(_ interventions: [FinancialRecord]) -> Double {
        interventions.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Section (embedded in ApplianceDetailSheet)

struct ApplianceServiceBookSection: View {
    let appliance: Appliance

    @Environment(FinancialService.self) private var financialService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings

    @State private var showAddIntervention = false

    private var interventions: [FinancialRecord] {
        ApplianceServiceLog.interventions(in: financialService.records, appliance: appliance)
    }
    private var totalRepairs: Double { ApplianceServiceLog.totalRepairs(interventions) }
    /// Repairs ≥ half the purchase price — the replace-it signal. Only shown
    /// when a purchase price exists; we never guess one.
    private var replacementSignal: Bool {
        guard let price = appliance.purchasePrice, price > 0 else { return false }
        return totalRepairs >= price / 2
    }

    private func money(_ amount: Double, currency: String) -> String {
        currencyService.formatted(amount, from: currency, preferred: appSettings.preferredCurrency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("service_book_title")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .tracking(0.5)
                Spacer()
                Button { showAddIntervention = true } label: {
                    Label("service_book_add", systemImage: "plus.circle.fill")
                        .font(AppFont.captionEmphasis)
                }
            }
            .padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if interventions.isEmpty {
                        Text("service_book_empty")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.lg)
                    } else {
                        ForEach(interventions) { record in
                            interventionRow(record)
                            Rectangle().fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5).padding(.leading, AppSpacing.lg)
                        }
                        totalsRows
                    }
                }
            }

            if replacementSignal {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.brandWarning)
                    Text("service_book_replace_signal")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
        }
        .sheet(isPresented: $showAddIntervention) {
            AddServiceInterventionSheet(appliance: appliance)
        }
    }

    private func interventionRow(_ record: FinancialRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(AppFont.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .glassCircle()
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(record.dateFormatted)
                    if let details = record.description, !details.isEmpty {
                        Text(verbatim: "·")
                        Text(details).lineLimit(1)
                    }
                }
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(0.45))
            }
            Spacer()
            Text(verbatim: money(record.amount, currency: record.currency))
                .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var totalsRows: some View {
        HStack {
            Text("service_book_total_repairs")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
            Text(verbatim: money(totalRepairs, currency: appSettings.preferredCurrency))
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)

        if let price = appliance.purchasePrice, price > 0 {
            Rectangle().fill(Color.primary.opacity(0.05))
                .frame(height: 0.5).padding(.leading, AppSpacing.lg)
            HStack {
                Text("service_book_tco")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Spacer()
                Text(verbatim: money(price + totalRepairs, currency: appSettings.preferredCurrency))
                    .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                    .foregroundStyle(replacementSignal ? Color.brandWarning : .primary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Add intervention

private struct AddServiceInterventionSheet: View {
    let appliance: Appliance

    @Environment(FinancialService.self) private var financialService
    @Environment(ContractorService.self) private var contractorService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var contractorId: UUID?
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }
    private var contractorName: String? {
        contractorId.flatMap { id in contractorService.contractors.first { $0.id == id }?.name }
    }

    var body: some View {
        FormScaffold(title: "service_book_add", canSave: canSave, isSaving: isSaving,
                     error: $error, onSave: { Task { await save() } }) {
            FormGroup {
                FormRow(icon: "wrench.and.screwdriver.fill") {
                    TextField(String(localized: "service_intervention_placeholder"), text: $title)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                }
            }
            FormGroup {
                FormRow(icon: "coloncurrencysign.circle") {
                    HStack(spacing: 8) {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        Text(appSettings.preferredCurrency)
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                }
            }
            FormGroup {
                DatePicker(selection: $date, in: ...Date(), displayedComponents: .date) {
                    Label("Date", systemImage: "calendar")
                        .font(AppFont.scaled(15))
                }
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
            }
            if !contractorService.contractors.isEmpty {
                FormGroup {
                    HStack(spacing: 12) {
                        Label("comm_externals", systemImage: "person.crop.circle")
                            .font(AppFont.scaled(15))
                        Spacer()
                        Picker("", selection: $contractorId) {
                            Text("service_no_contractor").tag(UUID?.none)
                            ForEach(contractorService.contractors) { c in
                                Text(c.name).tag(UUID?.some(c.id))
                            }
                        }
                        .tint(Color.primary.opacity(AppOpacity.emphasis))
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                }
            }
            FormGroup {
                FormRow(icon: "note.text") {
                    TextField(String(localized: "Notes"), text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                }
            }
        }
        .task { if contractorService.contractors.isEmpty { await contractorService.load() } }
    }

    private func save() async {
        guard let amount else { return }
        isSaving = true
        defer { isSaving = false }

        struct NewRecord: Encodable {
            let property_id: String
            let title: String
            let amount: Double
            let currency: String
            let type: String
            let category: String
            let date: String
            let description: String?
            let tags: [String]
        }
        let details = [contractorName, notes.isEmpty ? nil : notes]
            .compactMap { $0 }.joined(separator: " · ")
        do {
            try await supabase.from("financial_records").insert(NewRecord(
                property_id: appliance.propertyId.uuidString,
                title: title.trimmingCharacters(in: .whitespaces),
                amount: amount,
                currency: appSettings.preferredCurrency,
                type: "expense",
                category: "appliance",
                date: AppDate.dayString(from: date),
                description: details.isEmpty ? nil : details,
                tags: [ApplianceServiceLog.serviceTag, ApplianceServiceLog.tag(for: appliance.id)]
            )).execute()
            await financialService.load()
            HapticFeedback.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
