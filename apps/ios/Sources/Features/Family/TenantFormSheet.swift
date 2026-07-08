import SwiftUI

// MARK: - Dedicated tenant form
//
// A professional add-tenant flow: identity, contact, full lease details
// (dates, rent, deposit, payment day, occupants) and notes. Replaces the
// generic family-member sheet for tenants — and, unlike it, every save error
// is surfaced in an alert instead of being swallowed (the old flow dismissed
// as if it had succeeded, which is why "adding a tenant didn't work").

struct TenantFormSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss
    let propertyId: UUID?
    var propertyName: String? = nil

    // Identity
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var color = "#A29BFE"
    // Contact
    @State private var email = ""
    @State private var phone = ""
    // Lease
    @State private var leaseStart = Date()
    @State private var hasEndDate = true
    @State private var leaseEnd = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var rentText = ""
    @State private var currency = "EUR"
    @State private var depositText = ""
    @State private var paymentDay = 1
    @State private var occupants = 1
    @State private var notes = ""
    @State private var sendInvite = true

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let currencies = ["EUR", "RON", "USD", "GBP"]

    private var fullName: String {
        [firstName.trimmingCharacters(in: .whitespaces),
         lastName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    private var canSave: Bool { !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        FormScaffold(title: "New Tenant", saveLabel: "Add",
                     canSave: canSave, isSaving: isSaving,
                     error: $errorMessage, onSave: { Task { await save() } }) {
                        header
                        section("IDENTITY") {
                            fieldRow(icon: "person.fill", tint: .purple, placeholder: "First name *", text: $firstName)
                            divider
                            fieldRow(icon: "person", tint: .purple, placeholder: "Last name", text: $lastName)
                        }
                        section("CONTACT") {
                            fieldRow(icon: "envelope.fill", tint: .blue, placeholder: "Email", text: $email,
                                     keyboard: .emailAddress)
                            divider
                            fieldRow(icon: "phone.fill", tint: Color.brandSuccess, placeholder: "Phone", text: $phone,
                                     keyboard: .phonePad)
                        }
                        section("LEASE") {
                            DatePicker(selection: $leaseStart, displayedComponents: .date) {
                                Label("Lease start", systemImage: "calendar")
                                    .font(AppFont.subheadline).foregroundStyle(.primary)
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                            divider
                            Toggle(isOn: $hasEndDate.animation(.snappy)) {
                                Label("Fixed term", systemImage: "calendar.badge.checkmark")
                                    .font(AppFont.subheadline).foregroundStyle(.primary)
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                            if hasEndDate {
                                divider
                                DatePicker(selection: $leaseEnd, in: leaseStart..., displayedComponents: .date) {
                                    Label("Lease end", systemImage: "calendar.badge.exclamationmark")
                                        .font(AppFont.subheadline).foregroundStyle(.primary)
                                }
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                            }
                        }
                        section("RENT") {
                            HStack(spacing: AppSpacing.md) {
                                Label("Monthly rent", systemImage: "banknote.fill")
                                    .font(AppFont.subheadline).foregroundStyle(.primary)
                                Spacer()
                                TextField("0", text: $rentText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                Picker("", selection: $currency) {
                                    ForEach(currencies, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden().tint(.secondary)
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                            divider
                            HStack {
                                Label("Deposit", systemImage: "lock.shield.fill")
                                    .font(AppFont.subheadline).foregroundStyle(.primary)
                                Spacer()
                                TextField("0", text: $depositText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                                Text(currency).foregroundStyle(.secondary).font(AppFont.subheadline)
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                            divider
                            HStack {
                                Label("Payment day", systemImage: "calendar.day.timeline.left")
                                    .font(AppFont.subheadline).foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $paymentDay) {
                                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                                }
                                .labelsHidden().tint(.secondary)
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
                            divider
                            HStack {
                                Label("Occupants", systemImage: "person.2.fill")
                                    .font(AppFont.subheadline).foregroundStyle(.primary)
                                Spacer()
                                Stepper("\(occupants)", value: $occupants, in: 1...20)
                                    .fixedSize()
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
                        }
                        section("NOTES") {
                            TextField("Parking spot, house rules, meter readings…", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                        }
                        if !email.trimmingCharacters(in: .whitespaces).isEmpty {
                            section("ACCESS") {
                                Toggle(isOn: $sendInvite) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Send invitation email")
                                            .font(AppFont.subheadline).foregroundStyle(.primary)
                                        Text("The tenant gets app access with the tenant role")
                                            .font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                                    }
                                }
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                            }
                        }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle().fill((Color(hex: color) ?? .purple).opacity(0.2))
                    .frame(width: 72, height: 72)
                Image(systemName: "key.fill")
                    .font(AppFont.scaled(28, weight: .semibold))
                    .foregroundStyle(Color(hex: color) ?? .purple)
            }
            Text(fullName.isEmpty ? String(localized: "New Tenant") : fullName)
                .font(AppFont.title3).foregroundStyle(.primary)
        }
        .padding(.top, AppSpacing.xs)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)
            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    private func fieldRow(icon: String, tint: Color, placeholder: LocalizedStringKey,
                          text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppFont.footnote).foregroundStyle(tint).frame(width: 22)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline))
            .frame(height: 0.5).padding(.leading, 52)
    }

    // MARK: - Save

    private func number(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    private var emailIsValid: Bool {
        // Light-weight sanity check; the server still validates properly.
        let pattern = #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#
        return trimmedEmail.range(of: pattern, options: .regularExpression) != nil
    }

    private func save() async {
        guard let pid = propertyId else {
            errorMessage = String(localized: "Please set up your property first in Settings.")
            return
        }
        // Validate BEFORE creating anything: an invite with a bad address would
        // fail after the tenant row exists, leaving a half-added tenant.
        if sendInvite, !trimmedEmail.isEmpty, !emailIsValid {
            errorMessage = String(localized: "The e-mail address doesn't look valid. Fix it or turn off the invitation.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            guard let member = try await familyService.add(
                name: fullName, role: "tenant",
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                color: color, propertyId: pid,
                birthday: nil, socialLinks: []
            ) else {
                errorMessage = String(localized: "You need to be signed in to add a tenant.")
                return
            }

            try await familyService.saveLease(
                memberId: member.id, propertyId: pid,
                leaseStart: leaseStart,
                leaseEnd: hasEndDate ? leaseEnd : nil,
                monthlyRent: number(from: rentText),
                currency: currency,
                deposit: number(from: depositText),
                paymentDay: paymentDay,
                occupants: occupants,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
            )

            if sendInvite, !trimmedEmail.isEmpty {
                if let err = await familyService.sendInvite(
                    to: trimmedEmail, name: fullName, role: "tenant",
                    propertyId: pid, propertyName: propertyName) {
                    // Atomic add: a failed invite rolls the tenant back so
                    // nothing half-added lingers in members or chat.
                    await familyService.delete(member)
                    errorMessage = String(localized: "The tenant was not added because the invitation failed:") + " " + err
                    return
                }
            }

            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
