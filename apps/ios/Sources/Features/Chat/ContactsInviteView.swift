import SwiftUI
import Contacts

// MARK: - WhatsApp-style contacts + invite
//
// Tapping "New contact" opens the phone's address book (like WhatsApp): people
// already in your household surface at the top so you can jump straight into a
// chat, and everyone else gets an "Invite" button that adds them as a guest and
// sends them a join link (by email, or via the share sheet for phone-only
// contacts). A manual-entry fallback covers people not in the address book.

// The invite landing the share sheet points at. The household owns this domain;
// point it at a real install/landing page when one exists.
enum PRVIOInvite {
    static let landing = URL(string: "https://xparvu.com")!
}

struct DeviceContact: Identifiable, Equatable {
    let id: String
    let name: String
    let phones: [String]
    let emails: [String]

    var primaryDetail: String? { emails.first ?? phones.first }
    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
    /// Digits-only phone numbers for matching against members regardless of
    /// formatting (+40, spaces, dashes…).
    var normalizedPhones: [String] { phones.map { $0.filter(\.isNumber) } }
    var normalizedEmails: [String] { emails.map { $0.lowercased() } }
}

@MainActor
@Observable
final class DeviceContactsLoader {
    enum LoadState { case idle, loading, denied, loaded }

    var state: LoadState = .idle
    var contacts: [DeviceContact] = []

    func loadIfNeeded() async {
        guard state == .idle else { return }
        state = .loading
        let status = CNContactStore.authorizationStatus(for: .contacts)
        var granted = status == .authorized
        if status == .notDetermined {
            granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
        }
        guard granted else { state = .denied; return }
        contacts = await Self.fetch()
        state = .loaded
    }

    // Enumerating the address book is I/O heavy — keep it off the main actor.
    private static func fetch() async -> [DeviceContact] {
        await Task.detached(priority: .userInitiated) {
            let keys = [
                CNContactGivenNameKey, CNContactFamilyNameKey,
                CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var out: [DeviceContact] = []
            try? CNContactStore().enumerateContacts(with: request) { c, _ in
                let name = [c.givenName, c.familyName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                let phones = c.phoneNumbers.map { $0.value.stringValue }
                let emails = c.emailAddresses.map { $0.value as String }
                guard !name.isEmpty, !phones.isEmpty || !emails.isEmpty else { return }
                out.append(DeviceContact(id: c.identifier, name: name, phones: phones, emails: emails))
            }
            return out
        }.value
    }
}

struct ContactsInviteView: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    /// Opens a direct chat with an already-joined member.
    let onOpenMember: (FamilyMember) -> Void
    /// Falls back to the manual add-contact form.
    let onManualEntry: () -> Void

    @State private var loader = DeviceContactsLoader()
    @State private var search = ""
    @State private var invitedIds: Set<String> = []
    @State private var invitingId: String?
    @State private var shareItems: [Any]?
    @State private var banner: String?

    private var propertyId: UUID? { propertyService.primary?.id }

    private var filtered: [DeviceContact] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return loader.contacts }
        return loader.contacts.filter {
            $0.name.lowercased().contains(q)
                || $0.phones.contains { $0.contains(q) }
                || $0.emails.contains { $0.lowercased().contains(q) }
        }
    }

    /// email/phone → member, built once so partitioning is O(contacts), not
    /// O(contacts × members).
    private var memberIndex: [String: FamilyMember] {
        var index: [String: FamilyMember] = [:]
        for m in familyService.members {
            if let e = m.email?.lowercased(), !e.isEmpty { index[e] = m }
            if let p = m.phone?.filter(\.isNumber), !p.isEmpty { index[p] = m }
        }
        return index
    }

    private func matched(_ c: DeviceContact, in index: [String: FamilyMember]) -> FamilyMember? {
        for e in c.normalizedEmails where index[e] != nil { return index[e] }
        for p in c.normalizedPhones where index[p] != nil { return index[p] }
        return nil
    }

    // Partition once per render into "on PRVIO" and "to invite".
    private var partition: (onPRVIO: [(DeviceContact, FamilyMember)], toInvite: [DeviceContact]) {
        let index = memberIndex
        var joined: [(DeviceContact, FamilyMember)] = []
        var invite: [DeviceContact] = []
        for c in filtered {
            if let m = matched(c, in: index) { joined.append((c, m)) } else { invite.append(c) }
        }
        return (joined, invite)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                content
            }
            .navigationTitle("New contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { onManualEntry() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Enter manually")
                }
            }
            .task { await loader.loadIfNeeded() }
            .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
                if let items = shareItems { ShareSheet(activityItems: items) }
            }
            .overlay(alignment: .bottom) {
                if let banner {
                    Text(banner)
                        .font(AppFont.footnote).foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    @ViewBuilder private var content: some View {
        switch loader.state {
        case .idle, .loading:
            VStack { Spacer(); ProgressView().tint(.primary); Spacer() }
        case .denied:
            deniedState
        case .loaded:
            if loader.contacts.isEmpty { emptyState } else { list }
        }
    }

    private var list: some View {
        let parts = partition
        return List {
            Section {
                Button { onManualEntry() } label: {
                    Label("Add manually", systemImage: "keyboard")
                        .foregroundStyle(Color.accentColor)
                }
                .listRowBackground(Color.primary.opacity(0.04))
            }

            if !parts.onPRVIO.isEmpty {
                Section("On PRVIO") {
                    ForEach(parts.onPRVIO, id: \.0.id) { c, member in
                        Button {
                            onOpenMember(member)
                        } label: {
                            contactRow(c, trailing: {
                                Image(systemName: "bubble.left.fill")
                                    .font(AppFont.scaled(15))
                                    .foregroundStyle(Color.accentColor)
                            })
                        }
                        .listRowBackground(Color.primary.opacity(0.04))
                    }
                }
            }

            if !parts.toInvite.isEmpty {
                Section("Invite to PRVIO") {
                    ForEach(parts.toInvite) { c in
                        contactRow(c, trailing: { inviteButton(c) })
                            .listRowBackground(Color.primary.opacity(0.04))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: "Caută un nume sau un număr")
    }

    private func contactRow<Trailing: View>(_ c: DeviceContact,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.18))
                Text(c.initials.isEmpty ? "?" : c.initials)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(AppFont.subheadline).foregroundStyle(.primary).lineLimit(1)
                if let detail = c.primaryDetail {
                    Text(detail).font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private func inviteButton(_ c: DeviceContact) -> some View {
        if invitedIds.contains(c.id) {
            Label("Invited", systemImage: "checkmark")
                .font(AppFont.caption2).foregroundStyle(Color.brandSuccess)
        } else if invitingId == c.id {
            ProgressView()
        } else {
            Button {
                Task { await invite(c) }
            } label: {
                Text("Invite")
                    .font(AppFont.label).foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func invite(_ c: DeviceContact) async {
        guard invitingId == nil else { return }
        invitingId = c.id
        defer { invitingId = nil }

        let email = c.emails.first
        let phone = c.phones.first
        // Add them to the household as a chat-only guest (elevate later from
        // Members). We keep going even if this throws — a share-sheet invite is
        // still useful — but surface the failure.
        do {
            try await familyService.add(
                name: c.name, role: "guest",
                email: email, phone: phone,
                color: Self.color(for: c.name),
                propertyId: propertyId, birthday: nil, socialLinks: []
            )
        } catch {
            show(String(localized: "Couldn't add contact: \(error.localizedDescription)"))
            return
        }

        if let email, !email.isEmpty {
            // Real join link, emailed by the invite function.
            if let err = await familyService.sendInvite(
                to: email, name: c.name, role: "guest",
                propertyId: propertyId, propertyName: propertyService.primary?.name) {
                show(String(localized: "Added, but the invite email failed: \(err)"))
            } else {
                markInvited(c); HapticFeedback.success()
                show(String(localized: "Invitation sent to \(c.name)"))
            }
        } else {
            // Phone-only: hand off to the share sheet so the user can text them.
            markInvited(c); HapticFeedback.success()
            let text = String(localized: "\(c.name), te invit în PRVIO 🏠 — casa noastră digitală. Hai să vorbim în chat!")
            shareItems = [text, PRVIOInvite.landing]
        }
    }

    private func markInvited(_ c: DeviceContact) {
        withAnimation(.smooth(duration: 0.25)) { _ = invitedIds.insert(c.id) }
    }

    private func show(_ message: String) {
        withAnimation { banner = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { if banner == message { banner = nil } }
        }
    }

    private var deniedState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(AppFont.scaled(46, weight: .light))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            Text("Contacts access is off")
                .font(AppFont.headline).foregroundStyle(.primary)
            Text("Allow access to invite people straight from your address book.")
                .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(AppFont.subheadline)
            Button { onManualEntry() } label: { Text("Add manually").font(AppFont.subheadline) }
                .padding(.top, 4)
            Spacer()
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "person.2.slash",
            title: "No contacts found",
            actionLabel: "Add manually",
            action: onManualEntry
        )
    }

    // Stable per-name color so a contact looks consistent between sessions.
    // (Swift's Hasher is seeded per process, so we sum scalars instead.)
    private static func color(for name: String) -> String {
        let swatches = ["#3B82F6", "#22C55E", "#A855F7", "#EF4444", "#F59E0B", "#14B8A6", "#EC4899", "#6366F1"]
        let seed = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return swatches[seed % swatches.count]
    }
}
