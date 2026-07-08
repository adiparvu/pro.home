import SwiftUI

// MARK: - Document Intelligence — dynamic form schema (phase D1)
//
// Not every field is shown up front: the chosen category decides which
// sections and fields appear, so a Contract asks for issuer + identifiers +
// value while a Photo asks for almost nothing. The schema is pure data, so
// the form renders itself and new categories are one table entry.

/// Every optional field the rich document record can carry, beyond the
/// always-present name + category + file.
enum DocField: String, CaseIterable, Hashable {
    // Classification
    case subcategory, description, tags, priority
    // Dates
    case issuedAt, expiresAt, renewAt, notifyAt
    // Issuer
    case issuerCompany, issuerContact, issuerPhone, issuerEmail, issuerWebsite, clientNumber
    // Identifiers
    case docNumber, series, contractCode, clientCode, fiscalCode, policyNumber, barcode
    // Financial
    case value, currency, vat, recurrence

    enum Kind { case text, multiline, date, money, percent, priorityPicker, recurrencePicker, tags }

    var kind: Kind {
        switch self {
        case .description:      return .multiline
        case .tags:             return .tags
        case .priority:         return .priorityPicker
        case .recurrence:       return .recurrencePicker
        case .issuedAt, .expiresAt, .renewAt, .notifyAt: return .date
        case .value:            return .money
        case .vat:              return .percent
        default:                return .text
        }
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .subcategory:   return "doc_f_subcategory"
        case .description:   return "doc_f_description"
        case .tags:          return "doc_f_tags"
        case .priority:      return "doc_f_priority"
        case .issuedAt:      return "doc_f_issued"
        case .expiresAt:     return "doc_f_expires"
        case .renewAt:       return "doc_f_renew"
        case .notifyAt:      return "doc_f_notify"
        case .issuerCompany: return "doc_f_company"
        case .issuerContact: return "doc_f_contact"
        case .issuerPhone:   return "doc_f_phone"
        case .issuerEmail:   return "doc_f_email"
        case .issuerWebsite: return "doc_f_website"
        case .clientNumber:  return "doc_f_client_number"
        case .docNumber:     return "doc_f_number"
        case .series:        return "doc_f_series"
        case .contractCode:  return "doc_f_contract_code"
        case .clientCode:    return "doc_f_client_code"
        case .fiscalCode:    return "doc_f_fiscal_code"
        case .policyNumber:  return "doc_f_policy"
        case .barcode:       return "doc_f_barcode"
        case .value:         return "doc_f_value"
        case .currency:      return "doc_f_currency"
        case .vat:           return "doc_f_vat"
        case .recurrence:    return "doc_f_recurrence"
        }
    }

    var placeholderKey: LocalizedStringKey? {
        switch self {
        case .issuerCompany: return "doc_ph_company"
        case .issuerEmail:   return "doc_ph_email"
        case .issuerWebsite: return "doc_ph_website"
        case .policyNumber:  return "doc_ph_policy"
        case .subcategory:   return "doc_ph_subcategory"
        default:             return nil
        }
    }
}

struct DocSection: Identifiable {
    var id: String { titleKey }
    let titleKey: LocalizedStringKey
    let icon: String
    let color: Color
    let fields: [DocField]
}

enum DocumentCategorySchema {

    /// The ordered dynamic sections for a category. The base name/scan/file/
    /// category rows are rendered by the form itself; these come after.
    static func sections(for category: String) -> [DocSection] {
        let classification = DocSection(
            titleKey: "doc_sec_classification", icon: "tag.fill", color: .purple,
            fields: [.subcategory, .priority, .tags, .description])

        switch category {
        case "contract":
            return [classification,
                dates([.issuedAt, .expiresAt, .renewAt, .notifyAt]),
                issuer([.issuerCompany, .issuerContact, .issuerPhone, .issuerEmail, .issuerWebsite, .clientNumber]),
                identifiers([.docNumber, .contractCode, .clientCode, .fiscalCode]),
                financial([.value, .currency, .recurrence])]
        case "invoice":
            return [classification,
                dates([.issuedAt, .expiresAt]),
                issuer([.issuerCompany, .clientNumber]),
                identifiers([.docNumber, .series, .fiscalCode]),
                financial([.value, .currency, .vat, .recurrence])]
        case "warranty":
            return [classification,
                dates([.issuedAt, .expiresAt, .notifyAt]),
                issuer([.issuerCompany, .issuerPhone, .issuerEmail, .issuerWebsite]),
                identifiers([.docNumber, .series, .barcode])]
        case "insurance":
            return [classification,
                dates([.issuedAt, .expiresAt, .renewAt, .notifyAt]),
                issuer([.issuerCompany, .issuerContact, .issuerPhone, .issuerEmail, .issuerWebsite]),
                identifiers([.policyNumber, .clientNumber, .fiscalCode]),
                financial([.value, .currency, .recurrence])]
        case "utility":
            return [classification,
                dates([.issuedAt, .expiresAt]),
                issuer([.issuerCompany, .issuerPhone, .clientNumber]),
                identifiers([.docNumber, .clientCode]),
                financial([.value, .currency, .vat, .recurrence])]
        case "tax":
            return [classification,
                dates([.issuedAt, .expiresAt, .notifyAt]),
                issuer([.issuerCompany]),
                identifiers([.docNumber, .fiscalCode]),
                financial([.value, .currency])]
        case "legal", "permit", "certificate":
            return [classification,
                dates([.issuedAt, .expiresAt, .renewAt]),
                issuer([.issuerCompany, .issuerContact, .issuerPhone]),
                identifiers([.docNumber, .series])]
        case "manual":
            return [classification,
                issuer([.issuerCompany, .issuerWebsite]),
                identifiers([.series, .barcode])]
        default: // photo, other
            return [classification, dates([.issuedAt, .expiresAt])]
        }
    }

    private static func dates(_ f: [DocField]) -> DocSection {
        DocSection(titleKey: "doc_sec_dates", icon: "calendar", color: .orange, fields: f)
    }
    private static func issuer(_ f: [DocField]) -> DocSection {
        DocSection(titleKey: "doc_sec_issuer", icon: "building.2.fill", color: .blue, fields: f)
    }
    private static func identifiers(_ f: [DocField]) -> DocSection {
        DocSection(titleKey: "doc_sec_identifiers", icon: "number", color: .teal, fields: f)
    }
    private static func financial(_ f: [DocField]) -> DocSection {
        DocSection(titleKey: "doc_sec_financial", icon: "creditcard.fill", color: .green, fields: f)
    }
}

// MARK: - Editable field state
//
// One mutable bag holding every possible field, so the form binds to it and
// only the schema decides what's visible. Text fields share a dictionary;
// dates and enums get their own typed slots.

@Observable
final class DocumentFieldState {
    var text: [DocField: String] = [:]
    var dates: [DocField: Date] = [:]
    var dateEnabled: [DocField: Bool] = [:]
    var priority: String = "normal"
    var recurrence: String = "one-off"
    var currency: String = "RON"
    var tags: [String] = []

    init() {}

    /// Seeds every field from an existing document — used by the edit sheet so
    /// add and edit share one dynamic form.
    init(seed doc: DocumentModel) {
        priority = doc.priority ?? (doc.isCritical ? "critical" : "normal")
        recurrence = doc.recurrence ?? "one-off"
        currency = doc.currency ?? "RON"
        tags = doc.tags
        text[.subcategory]   = doc.subcategory
        text[.issuerCompany] = doc.issuerCompany
        text[.issuerContact] = doc.issuerContact
        text[.issuerPhone]   = doc.issuerPhone
        text[.issuerEmail]   = doc.issuerEmail
        text[.issuerWebsite] = doc.issuerWebsite
        text[.clientNumber]  = doc.clientNumber
        text[.docNumber]     = doc.docNumber
        text[.series]        = doc.series
        text[.contractCode]  = doc.contractCode
        text[.clientCode]    = doc.clientCode
        text[.fiscalCode]    = doc.fiscalCode
        text[.policyNumber]  = doc.policyNumber
        text[.barcode]       = doc.barcode
        text[.description]   = doc.description
        if let v = doc.value { text[.value] = String(v) }
        if let v = doc.vat { text[.vat] = String(v) }
        seedDate(.issuedAt, doc.issuedAt)
        seedDate(.expiresAt, doc.expiresAt)
        seedDate(.renewAt, doc.renewAt)
        seedDate(.notifyAt, doc.notifyAt)
    }

    private func seedDate(_ f: DocField, _ iso: String?) {
        guard let iso, let d = AppDate.day(from: iso) else { return }
        dates[f] = d
        dateEnabled[f] = true
    }

    func string(_ f: DocField) -> String { text[f] ?? "" }

    /// Applies the current field state onto a copy of `doc` — used by edit.
    func apply(to doc: DocumentModel) -> DocumentModel {
        var d = doc
        d.subcategory   = trimmed(.subcategory)
        d.priority      = priority
        d.isCritical    = DocPriority.isCritical(priority)
        d.issuedAt      = dateString(.issuedAt)
        d.expiresAt     = dateString(.expiresAt)
        d.renewAt       = dateString(.renewAt)
        d.notifyAt      = dateString(.notifyAt)
        d.issuerCompany = trimmed(.issuerCompany)
        d.issuerContact = trimmed(.issuerContact)
        d.issuerPhone   = trimmed(.issuerPhone)
        d.issuerEmail   = trimmed(.issuerEmail)
        d.issuerWebsite = trimmed(.issuerWebsite)
        d.clientNumber  = trimmed(.clientNumber)
        d.docNumber     = trimmed(.docNumber)
        d.series        = trimmed(.series)
        d.contractCode  = trimmed(.contractCode)
        d.clientCode    = trimmed(.clientCode)
        d.fiscalCode    = trimmed(.fiscalCode)
        d.policyNumber  = trimmed(.policyNumber)
        d.barcode       = trimmed(.barcode)
        d.description   = trimmed(.description)
        d.value         = money(.value)
        d.currency      = money(.value) != nil ? currency : nil
        d.vat           = money(.vat)
        d.recurrence    = recurrence == "one-off" ? nil : recurrence
        d.tags          = tags
        return d
    }

    /// Non-empty trimmed text, or nil — what the service wants.
    func trimmed(_ f: DocField) -> String? {
        let v = (text[f] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    func money(_ f: DocField) -> Double? {
        guard let raw = trimmed(f)?.replacingOccurrences(of: ",", with: ".") else { return nil }
        return Double(raw)
    }

    /// A yyyy-MM-dd string when the field's toggle is on, else nil.
    func dateString(_ f: DocField) -> String? {
        guard dateEnabled[f] == true, let d = dates[f] else { return nil }
        return ISO8601DateFormatter.yearMonthDay.string(from: d)
    }
}

enum DocPriority {
    static let all = ["normal", "important", "critical", "urgent"]
    static func label(_ p: String) -> LocalizedStringKey {
        switch p {
        case "important": return "doc_prio_important"
        case "critical":  return "doc_prio_critical"
        case "urgent":    return "doc_prio_urgent"
        default:          return "doc_prio_normal"
        }
    }
    static func color(_ p: String) -> Color {
        switch p {
        case "important": return .blue
        case "critical":  return .orange
        case "urgent":    return .red
        default:          return .secondary
        }
    }
    static func isCritical(_ p: String) -> Bool { p == "critical" || p == "urgent" }
}

enum DocRecurrence {
    static let all = ["one-off", "monthly", "quarterly", "yearly"]
    static func label(_ r: String) -> LocalizedStringKey {
        switch r {
        case "monthly":   return "doc_rec_monthly"
        case "quarterly": return "doc_rec_quarterly"
        case "yearly":    return "doc_rec_yearly"
        default:          return "doc_rec_oneoff"
        }
    }
    /// Localized plain String — for detail rows that render a value string.
    static func text(_ r: String) -> String {
        switch r {
        case "monthly":   return String(localized: "doc_rec_monthly")
        case "quarterly": return String(localized: "doc_rec_quarterly")
        case "yearly":    return String(localized: "doc_rec_yearly")
        default:          return String(localized: "doc_rec_oneoff")
        }
    }
}

// MARK: - Dynamic section + field renderers

struct DocSectionView: View {
    let section: DocSection
    @Bindable var state: DocumentFieldState

    var body: some View {
        FormGroup(title: section.titleKey) {
            ForEach(Array(section.fields.enumerated()), id: \.element) { idx, field in
                if idx > 0 { FormDivider() }
                DocFieldRow(field: field, tint: section.color, state: state)
            }
        }
    }
}

struct DocFieldRow: View {
    let field: DocField
    let tint: Color
    @Bindable var state: DocumentFieldState

    private var textBinding: Binding<String> {
        Binding(get: { state.text[field] ?? "" }, set: { state.text[field] = $0 })
    }
    private var dateBinding: Binding<Date> {
        Binding(get: { state.dates[field] ?? Date() }, set: { state.dates[field] = $0 })
    }
    private var dateOn: Binding<Bool> {
        Binding(get: { state.dateEnabled[field] ?? false }, set: { state.dateEnabled[field] = $0 })
    }

    var body: some View {
        switch field.kind {
        case .text:
            FormRow(icon: iconFor(field), tint: tint) {
                Text(field.labelKey).font(AppFont.scaled(15)).foregroundStyle(.primary)
                Spacer(minLength: 12)
                TextField(field.placeholderKey ?? "", text: textBinding)
                    .font(AppFont.scaled(15)).multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.primary.opacity(0.75)).tint(.accentColor)
                    .autocorrectionDisabled()
                    .keyboardType(keyboard(field))
                    .textContentType(contentType(field))
            }
        case .multiline:
            FormRow(icon: "text.alignleft", tint: tint) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.labelKey).font(AppFont.label).foregroundStyle(.secondary)
                    TextField("", text: textBinding, axis: .vertical)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        .lineLimit(1...4)
                }
            }
        case .date:
            VStack(spacing: 0) {
                FormRow(icon: "calendar", tint: tint) {
                    Text(field.labelKey).font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: dateOn).labelsHidden().tint(.accentColor)
                }
                if state.dateEnabled[field] == true {
                    FormDivider()
                    DatePicker("", selection: dateBinding, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 8)
                }
            }
        case .money:
            FormRow(icon: "banknote", tint: tint) {
                Text(field.labelKey).font(AppFont.scaled(15)).foregroundStyle(.primary)
                Spacer(minLength: 12)
                TextField("0", text: textBinding)
                    .font(AppFont.scaled(15)).multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.primary.opacity(0.75)).tint(.accentColor)
                    .keyboardType(.decimalPad)
                Menu {
                    Picker("", selection: $state.currency) {
                        ForEach(["RON", "EUR", "USD", "GBP"], id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    Text(state.currency).font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        case .percent:
            FormRow(icon: "percent", tint: tint) {
                Text(field.labelKey).font(AppFont.scaled(15)).foregroundStyle(.primary)
                Spacer(minLength: 12)
                TextField("0", text: textBinding)
                    .font(AppFont.scaled(15)).multilineTextAlignment(.trailing)
                    .foregroundStyle(Color.primary.opacity(0.75)).tint(.accentColor)
                    .keyboardType(.decimalPad)
            }
        case .priorityPicker:
            FormRow(icon: "flag.fill", tint: DocPriority.color(state.priority)) {
                Text(field.labelKey).font(AppFont.scaled(15)).foregroundStyle(.primary)
                Spacer()
                Menu {
                    Picker("", selection: $state.priority) {
                        ForEach(DocPriority.all, id: \.self) { Text(DocPriority.label($0)).tag($0) }
                    }
                } label: {
                    Text(DocPriority.label(state.priority))
                        .font(AppFont.scaled(14, weight: .medium))
                        .foregroundStyle(DocPriority.color(state.priority))
                }
            }
        case .recurrencePicker:
            FormRow(icon: "arrow.triangle.2.circlepath", tint: tint) {
                Text(field.labelKey).font(AppFont.scaled(15)).foregroundStyle(.primary)
                Spacer()
                Menu {
                    Picker("", selection: $state.recurrence) {
                        ForEach(DocRecurrence.all, id: \.self) { Text(DocRecurrence.label($0)).tag($0) }
                    }
                } label: {
                    Text(DocRecurrence.label(state.recurrence))
                        .font(AppFont.scaled(14, weight: .medium)).foregroundStyle(.accentColor)
                }
            }
        case .tags:
            FormRow(icon: "tag", tint: tint) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.labelKey).font(AppFont.label).foregroundStyle(.secondary)
                    if !state.tags.isEmpty {
                        FlowTags(tags: state.tags) { tag in state.tags.removeAll { $0 == tag } }
                    }
                    TextField("doc_ph_tags", text: textBinding)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        .autocorrectionDisabled()
                        .onSubmit { commitTag() }
                }
            }
        }
    }

    private func commitTag() {
        let t = (state.text[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !state.tags.contains(t) else { return }
        state.tags.append(t)
        state.text[field] = ""
    }

    private func iconFor(_ f: DocField) -> String {
        switch f {
        case .subcategory:   return "square.grid.2x2"
        case .issuerCompany: return "building.2"
        case .issuerContact: return "person"
        case .issuerPhone:   return "phone"
        case .issuerEmail:   return "envelope"
        case .issuerWebsite: return "globe"
        case .clientNumber, .clientCode: return "person.text.rectangle"
        case .docNumber, .series: return "number"
        case .contractCode:  return "doc.text"
        case .fiscalCode:    return "building.columns"
        case .policyNumber:  return "shield"
        case .barcode:       return "barcode"
        default:             return "circle"
        }
    }
    private func keyboard(_ f: DocField) -> UIKeyboardType {
        switch f {
        case .issuerPhone: return .phonePad
        case .issuerEmail: return .emailAddress
        case .issuerWebsite: return .URL
        default: return .default
        }
    }
    private func contentType(_ f: DocField) -> UITextContentType? {
        switch f {
        case .issuerPhone: return .telephoneNumber
        case .issuerEmail: return .emailAddress
        case .issuerWebsite: return .URL
        case .issuerCompany: return .organizationName
        default: return nil
        }
    }
}

/// Tag chips with a tap-to-remove affordance. Horizontal scroll keeps the
/// row height stable no matter how many tags the user adds.
private struct FlowTags: View {
    let tags: [String]
    let onRemove: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag).font(AppFont.scaled(12, weight: .medium))
                        Image(systemName: "xmark").font(AppFont.scaled(9, weight: .bold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.accentColor.opacity(AppOpacity.tintedFill), in: Capsule())
                    .onTapGesture { onRemove(tag) }
                }
            }
        }
    }
}
