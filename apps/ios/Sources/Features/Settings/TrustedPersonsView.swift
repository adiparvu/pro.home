import SwiftUI
import Supabase

// MARK: - Model
//
// A row in the `trusted_persons` table (RLS: each user sees only their own
// rows). The capability flags are STORED on the account but not yet enforced
// by any backend flow — the footer says so plainly.

struct TrustedPerson: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var canEmergencyAccess: Bool = false
    var canApproveRecovery: Bool = false
    var canTransferOwnership: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, email
        case canEmergencyAccess   = "can_emergency_access"
        case canApproveRecovery   = "can_approve_recovery"
        case canTransferOwnership = "can_transfer_ownership"
    }

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "?")) + String((parts[1].first ?? "?"))
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - PostgREST payloads

private struct TrustedPersonInsert: Encodable {
    let id: String
    let user_id: String
    let name: String
    let email: String
    let can_emergency_access: Bool
    let can_approve_recovery: Bool
    let can_transfer_ownership: Bool

    init(_ person: TrustedPerson, userId: UUID) {
        id = person.id.uuidString
        user_id = userId.uuidString
        name = person.name
        email = person.email
        can_emergency_access = person.canEmergencyAccess
        can_approve_recovery = person.canApproveRecovery
        can_transfer_ownership = person.canTransferOwnership
    }
}

private struct TrustedPersonUpdate: Encodable {
    let name: String
    let email: String
    let can_emergency_access: Bool
    let can_approve_recovery: Bool
    let can_transfer_ownership: Bool

    init(_ person: TrustedPerson) {
        name = person.name
        email = person.email
        can_emergency_access = person.canEmergencyAccess
        can_approve_recovery = person.canApproveRecovery
        can_transfer_ownership = person.canTransferOwnership
    }
}

/// The shape the pre-account builds wrote to UserDefaults (default camelCase
/// Codable keys) — decoded once, migrated into the table, then deleted.
private struct LegacyTrustedPerson: Decodable {
    let id: UUID
    let name: String
    let email: String
    let canEmergencyAccess: Bool
    let canApproveRecovery: Bool
    let canTransferOwnership: Bool
}

// MARK: - Main view

struct TrustedPersonsView: View {
    @State private var persons: [TrustedPerson] = []
    @State private var showAdd = false
    @State private var editingPerson: TrustedPerson? = nil
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var syncFailed = false

    /// Pre-account device-local store; migrated silently into the table.
    private static let legacyKey = "prvio.trustedPersons"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                if isLoading {
                    loadingState
                } else if loadFailed && persons.isEmpty {
                    errorState
                } else if persons.isEmpty {
                    emptyState
                } else {
                    personsList
                }
                if !isLoading && !(loadFailed && persons.isEmpty) {
                    addButton
                }
                if syncFailed {
                    syncErrorText
                }
                footerText
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Persoane de încredere")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) {
            TrustedPersonSheet { person in
                Task { await add(person) }
            }
        }
        .sheet(item: $editingPerson) { person in
            TrustedPersonSheet(editing: person) { updated in
                Task { await update(updated) }
            }
        }
    }

    // MARK: - Persons list

    private var personsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Persoane de încredere")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 0) {
                ForEach(Array(persons.enumerated()), id: \.element.id) { idx, person in
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(AppOpacity.hairline))
                            .frame(height: 0.4)
                            .padding(.leading, 62)
                    }
                    Button {
                        editingPerson = person
                    } label: {
                        personRow(person)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editingPerson = person
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await delete(person) }
                        } label: {
                            Label("Șterge", systemImage: "trash")
                        }
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private func personRow(_ person: TrustedPerson) -> some View {
        HStack(spacing: 12) {
            // Initials circle
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.brandSkyBlue, Color(red: 0.55, green: 0.3, blue: 1.0)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)
                Text(person.initials)
                    .font(AppFont.scaled(14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Text(person.email)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineLimit(1)
                if person.canEmergencyAccess || person.canApproveRecovery || person.canTransferOwnership {
                    permissionTags(person)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(0.28))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    private func permissionTags(_ person: TrustedPerson) -> some View {
        HStack(spacing: 4) {
            if person.canEmergencyAccess {
                permTag("Urgență", color: .orange)
            }
            if person.canApproveRecovery {
                permTag("Recuperare", color: .blue)
            }
            if person.canTransferOwnership {
                permTag("Transfer", color: .purple)
            }
        }
    }

    private func permTag(_ label: String, color: Color) -> some View {
        Text(LocalizedStringKey(label))
            .font(AppFont.scaled(10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Loading / empty / error states

    private var loadingState: some View {
        ProgressView()
            .padding(.vertical, AppSpacing.xxl)
            .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "person.2.badge.key.fill",
            title: "Nicio persoană de încredere",
            message: "Adaugă persoane care te pot ajuta cu recuperarea contului"
        )
    }

    /// Honest failure: when the account list can't be fetched we say so —
    /// never an empty state that pretends the account has no trusted people.
    private var errorState: some View {
        EmptyStateView(
            icon: "wifi.exclamationmark",
            title: "trusted_persons_error_title",
            message: "trusted_persons_error_msg",
            actionLabel: "Retry",
            action: { Task { await load() } }
        )
    }

    private var syncErrorText: some View {
        Text("trusted_persons_sync_error")
            .font(AppFont.scaled(12))
            .foregroundStyle(Color.brandDanger)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.sm)
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            showAdd = true
            HapticFeedback.impact(.medium)
        } label: {
            Label("Adaugă persoană", systemImage: "plus")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // Honest copy: capabilities are stored on the account, but no backend
    // flow enforces them yet — say so instead of implying they work.
    private var footerText: some View {
        Text("trusted_persons_footer")
            .font(AppFont.scaled(12))
            .foregroundStyle(Color.primary.opacity(0.38))
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.sm)
    }

    // MARK: - Persistence (trusted_persons table, RLS self-only)

    private func load() async {
        await migrateLegacyStoreIfNeeded()
        do {
            persons = try await supabase.from("trusted_persons")
                .select("id,name,email,can_emergency_access,can_approve_recovery,can_transfer_ownership")
                .order("created_at")
                .execute().value
            loadFailed = false
            syncFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    /// Optimistic append; reverted honestly if the insert fails.
    private func add(_ person: TrustedPerson) async {
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        persons.append(person)
        do {
            _ = try await supabase.from("trusted_persons")
                .insert(TrustedPersonInsert(person, userId: userId))
                .execute()
            syncFailed = false
        } catch {
            persons.removeAll { $0.id == person.id }
            syncFailed = true
            HapticFeedback.error()
        }
    }

    /// Optimistic in-place edit (capability toggles included); reverted on failure.
    private func update(_ person: TrustedPerson) async {
        guard let idx = persons.firstIndex(where: { $0.id == person.id }) else { return }
        let previous = persons[idx]
        persons[idx] = person
        do {
            _ = try await supabase.from("trusted_persons")
                .update(TrustedPersonUpdate(person))
                .eq("id", value: person.id.uuidString)
                .execute()
            syncFailed = false
        } catch {
            if let i = persons.firstIndex(where: { $0.id == person.id }) {
                persons[i] = previous
            }
            syncFailed = true
            HapticFeedback.error()
        }
    }

    /// Optimistic removal; restored if the delete fails.
    private func delete(_ person: TrustedPerson) async {
        guard let idx = persons.firstIndex(where: { $0.id == person.id }) else { return }
        persons.remove(at: idx)
        do {
            _ = try await supabase.from("trusted_persons")
                .delete()
                .eq("id", value: person.id.uuidString)
                .execute()
            syncFailed = false
        } catch {
            persons.insert(person, at: min(idx, persons.count))
            syncFailed = true
            HapticFeedback.error()
        }
    }

    // MARK: - One-time silent migration (UserDefaults → table)
    //
    // Upsert keeps a retried migration idempotent (same client-side ids);
    // the key is removed only after the write succeeds, so a failed attempt
    // simply retries on the next visit. Silent by design.

    private func migrateLegacyStoreIfNeeded() async {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        guard let legacy = try? JSONDecoder().decode([LegacyTrustedPerson].self, from: data) else {
            // Undecodable leftovers can never migrate — drop them.
            defaults.removeObject(forKey: Self.legacyKey)
            return
        }
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        if legacy.isEmpty {
            defaults.removeObject(forKey: Self.legacyKey)
            return
        }
        let rows = legacy.map {
            TrustedPersonInsert(
                TrustedPerson(id: $0.id, name: $0.name, email: $0.email,
                              canEmergencyAccess: $0.canEmergencyAccess,
                              canApproveRecovery: $0.canApproveRecovery,
                              canTransferOwnership: $0.canTransferOwnership),
                userId: userId
            )
        }
        do {
            _ = try await supabase.from("trusted_persons")
                .upsert(rows)
                .execute()
            defaults.removeObject(forKey: Self.legacyKey)
        } catch { /* silent — next visit retries */ }
    }
}

// MARK: - Add / edit sheet

private struct TrustedPersonSheet: View {
    var editing: TrustedPerson? = nil
    let onSave: (TrustedPerson) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var canEmergencyAccess = false
    @State private var canApproveRecovery = false
    @State private var canTransferOwnership = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Info fields
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                .padding(.leading, AppSpacing.xxs)

                            VStack(spacing: 0) {
                                fieldRow(icon: "person.fill", color: .blue, placeholder: "Nume complet", text: $name, keyboard: .default)
                                rowDivider
                                fieldRow(icon: "envelope.fill", color: .indigo, placeholder: "Adresă email", text: $email, keyboard: .emailAddress)
                            }
                            .liquidGlass(cornerRadius: AppRadius.lg)
                        }

                        // Permissions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Permissions")
                                .font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                .padding(.leading, AppSpacing.xxs)

                            VStack(spacing: 0) {
                                toggleRow(icon: "exclamationmark.shield.fill", color: .orange,
                                          title: "Acces de urgență",
                                          subtitle: "Poate solicita acces în situații de urgență",
                                          isOn: $canEmergencyAccess)
                                rowDivider
                                toggleRow(icon: "checkmark.shield.fill", color: .blue,
                                          title: "Aprobare recuperare",
                                          subtitle: "Poate aproba recuperarea contului tău",
                                          isOn: $canApproveRecovery)
                                rowDivider
                                toggleRow(icon: "arrow.triangle.swap", color: .purple,
                                          title: "Transfer proprietate",
                                          subtitle: "Poate prelua proprietatea contului",
                                          isOn: $canTransferOwnership)
                            }
                            .liquidGlass(cornerRadius: AppRadius.lg)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                }
            }
            // Text() on each branch keeps the LocalizedStringKey overload —
            // a bare ternary of literals would resolve to String (verbatim).
            .navigationTitle(editing == nil ? Text("Adaugă persoană") : Text("trusted_person_edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        var person = editing ?? TrustedPerson(name: "", email: "")
                        person.name = name.trimmingCharacters(in: .whitespaces)
                        person.email = email.trimmingCharacters(in: .whitespaces)
                        person.canEmergencyAccess = canEmergencyAccess
                        person.canApproveRecovery = canApproveRecovery
                        person.canTransferOwnership = canTransferOwnership
                        onSave(person)
                        dismiss()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(isValid ? .blue : Color.primary.opacity(0.3))
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    email = editing.email
                    canEmergencyAccess = editing.canEmergencyAccess
                    canApproveRecovery = editing.canApproveRecovery
                    canTransferOwnership = editing.canTransferOwnership
                }
            }
        }
    }

    private func fieldRow(icon: String, color: Color, placeholder: LocalizedStringKey, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            TextField(placeholder, text: text)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 13)
    }

    private func toggleRow(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                Text(LocalizedStringKey(subtitle))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 13)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(AppOpacity.hairline))
            .frame(height: 0.4)
            .padding(.leading, 54)
    }
}
