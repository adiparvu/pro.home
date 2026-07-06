import SwiftUI
import Contacts
import ContactsUI

// MARK: - Contact sharing, the PRVIO way
//
// WhatsApp shows a contact; we make it actionable and household-aware.
// One payload format rides both message pipelines: the group chat sends it
// as attachmentType "contact", DMs (whose table has no attachment column)
// prefix the JSON with a marker glyph. Old "👤 name | phone" messages keep
// rendering as plain text — nothing breaks.

struct SharedContactPayload: Codable, Identifiable, Equatable {
    var name: String
    var phones: [String] = []
    var emails: [String] = []
    /// Tiny thumbnail (base64 JPEG) so the card shows a real face.
    var avatar: String? = nil

    var id: String { name + (phones.first ?? "") }

    static let dmMarker = "📇"

    static func encodeGroup(_ payloads: [SharedContactPayload]) -> String? {
        (try? JSONEncoder().encode(payloads)).flatMap { String(data: $0, encoding: .utf8) }
    }
    static func encodeDM(_ payloads: [SharedContactPayload]) -> String? {
        encodeGroup(payloads).map { dmMarker + $0 }
    }
    static func decode(_ body: String?) -> [SharedContactPayload] {
        guard var s = body else { return [] }
        if s.hasPrefix(dmMarker) { s.removeFirst(dmMarker.count) }
        guard let data = s.data(using: .utf8),
              let payloads = try? JSONDecoder().decode([SharedContactPayload].self, from: data)
        else { return [] }
        return payloads
    }

    var avatarImage: UIImage? {
        avatar.flatMap { Data(base64Encoded: $0) }.flatMap(UIImage.init(data:))
    }
}

extension Message {
    var isContactShare: Bool { attachmentType == "contact" }
}

extension DirectMessage {
    var isContactShare: Bool { body.hasPrefix(SharedContactPayload.dmMarker + "[") }
}

// MARK: - Multi-select picker (household first, then the address book)

struct ContactMultiPicker: View {
    let members: [FamilyMember]
    let onSend: ([SharedContactPayload]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: [SharedContactPayload] = []
    @State private var deviceContacts: [SharedContactPayload] = []
    @State private var accessDenied = false

    private var householdPayloads: [SharedContactPayload] {
        members.map { m in
            SharedContactPayload(name: m.name,
                                 phones: [m.phone].compactMap { $0 }.filter { !$0.isEmpty },
                                 emails: [m.email].compactMap { $0 }.filter { !$0.isEmpty })
        }
    }

    private func matches(_ p: SharedContactPayload) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return p.name.localizedCaseInsensitiveContains(q)
            || p.phones.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    private func isSelected(_ p: SharedContactPayload) -> Bool { selected.contains(p) }

    private func toggle(_ p: SharedContactPayload) {
        HapticFeedback.selection()
        if let i = selected.firstIndex(of: p) { selected.remove(at: i) }
        else { selected.append(p) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !selected.isEmpty { chips }
                List {
                    let filteredHousehold = householdPayloads.filter(matches)
                    let filteredDevice = deviceContacts.filter(matches)
                    if !search.isEmpty && filteredHousehold.isEmpty && filteredDevice.isEmpty {
                        Section {
                            EmptyStateView(icon: "magnifyingglass", title: "No results")
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    if !filteredHousehold.isEmpty {
                        Section(String(localized: "Casa ta")) {
                            ForEach(filteredHousehold) { p in row(p) }
                        }
                    }
                    if !filteredDevice.isEmpty {
                        Section(String(localized: "Din Contacte")) {
                            ForEach(filteredDevice) { p in row(p) }
                        }
                    } else if accessDenied {
                        Section {
                            Text("Permite accesul la Contacte din Setări pentru a partaja din agendă.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search…"))
            .navigationTitle(Text("Distribuie contacte"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let picked = selected
                        dismiss()
                        onSend(picked)
                    } label: {
                        Text(selected.count > 1
                             ? String(format: String(localized: "Trimite (%d)"), selected.count)
                             : String(localized: "Trimite"))
                            .font(AppFont.subheadline)
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .task { await loadDeviceContacts() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(selected) { p in
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            ContactAvatar(payload: p, size: 46)
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(.systemGray))
                                .offset(x: 4, y: -4)
                        }
                        Text(p.name.split(separator: " ").first.map(String.init) ?? p.name)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 52)
                    }
                    .onTapGesture { toggle(p) }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
        .animation(.snappy(duration: 0.2), value: selected)
    }

    private func row(_ p: SharedContactPayload) -> some View {
        Button { toggle(p) } label: {
            HStack(spacing: 12) {
                ContactAvatar(payload: p, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    if let phone = p.phones.first {
                        Text(phone)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected(p) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(isSelected(p) ? Color.accentColor : Color.primary.opacity(0.22))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected(p) ? [.isButton, .isSelected] : .isButton)
    }

    private func loadDeviceContacts() async {
        let store = CNContactStore()
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted else { accessDenied = true; return }
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactThumbnailImageDataKey,
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        // Enumeration is synchronous; hop off the main actor for the walk.
        let payloads: [SharedContactPayload] = await Task.detached(priority: .userInitiated) {
            var out: [SharedContactPayload] = []
            try? store.enumerateContacts(with: request) { c, _ in
                let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let display = name.isEmpty ? c.organizationName : name
                guard !display.isEmpty else { return }
                out.append(SharedContactPayload(
                    name: display,
                    phones: c.phoneNumbers.map { $0.value.stringValue },
                    emails: c.emailAddresses.map { String($0.value) },
                    avatar: c.thumbnailImageData?.base64EncodedString()
                ))
            }
            return out
        }.value
        deviceContacts = payloads
    }
}

// MARK: - Avatar (photo → initials on a stable tint)

struct ContactAvatar: View {
    let payload: SharedContactPayload
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            if let img = payload.avatarImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                let tint = MessageBubble.color(for: payload.name)
                Circle().fill(tint.opacity(0.18))
                Text(MessageBubble.initials(from: payload.name))
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - The card bubble

struct ContactCardBubble: View {
    let payloads: [SharedContactPayload]
    let isOwn: Bool
    let bubbleColor: Color
    var hasTail: Bool = true
    var members: [FamilyMember] = []

    @State private var showDetail = false

    private var onBubble: Color { isOwn ? bubbleColor.readableText : .primary }
    private var title: String {
        guard let first = payloads.first else { return "" }
        return payloads.count == 1 ? first.name
            : String(format: String(localized: "%@ și încă %d"), first.name, payloads.count - 1)
    }

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 10) {
                // Up to three overlapping faces.
                HStack(spacing: -12) {
                    ForEach(payloads.prefix(3)) { p in
                        ContactAvatar(payload: p, size: 38)
                            .overlay(Circle().strokeBorder(
                                isOwn ? bubbleColor : Color(.systemBackground), lineWidth: 1.5))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOwn ? onBubble : .primary)
                        .lineLimit(1)
                    Text(payloads.count == 1
                         ? (payloads.first?.phones.first ?? String(localized: "Contact"))
                         : String(format: String(localized: "%d contacte"), payloads.count))
                        .font(.system(size: 12))
                        .foregroundStyle((isOwn ? onBubble : Color.primary).opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle((isOwn ? onBubble : Color.primary).opacity(0.4))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 10)
            .frame(minWidth: 200, maxWidth: 250, alignment: .leading)
            .background(isOwn ? bubbleColor : Color.primary.opacity(0.08),
                        in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SharedContactDetailSheet(payloads: payloads, members: members)
        }
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Detail: every shared contact, actionable

struct SharedContactDetailSheet: View {
    let payloads: [SharedContactPayload]
    var members: [FamilyMember] = []
    @Environment(\.dismiss) private var dismiss
    @State private var saving: SharedContactPayload?

    var body: some View {
        NavigationStack {
            List {
                ForEach(payloads) { p in
                    Section {
                        HStack(spacing: 12) {
                            ContactAvatar(payload: p, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .font(.system(size: 17, weight: .semibold))
                                if isHouseholdMember(p) {
                                    Label(String(localized: "Membru al casei"), systemImage: "house.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.brandSuccess)
                                }
                            }
                        }
                        .padding(.vertical, 2)

                        ForEach(p.phones, id: \.self) { phone in
                            Label(phone, systemImage: "phone")
                                .font(.system(size: 15))
                        }
                        ForEach(p.emails, id: \.self) { email in
                            Label(email, systemImage: "envelope")
                                .font(.system(size: 15))
                        }

                        actionRow(p)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(Text("Contacte"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents(payloads.count == 1 ? [.medium, .large] : [.large])
        .sheet(item: $saving) { p in
            SystemContactSaveSheet(payload: p)
        }
    }

    private func isHouseholdMember(_ p: SharedContactPayload) -> Bool {
        members.contains { m in
            m.name.caseInsensitiveCompare(p.name) == .orderedSame
                || (m.phone.map { p.phones.contains($0) } ?? false)
                || (m.email.map { p.emails.contains($0) } ?? false)
        }
    }

    private func actionRow(_ p: SharedContactPayload) -> some View {
        // Native pattern (Apple's contact card): Liquid Glass circles with
        // primary glyphs — never tinted rectangles.
        HStack(spacing: 0) {
            Group {
                if let phone = p.phones.first {
                    let digits = phone.filter { $0.isNumber || $0 == "+" }
                    GlassActionButton(icon: "phone.fill", label: "Sună") {
                        open("tel://\(digits)")
                    }
                    GlassActionButton(icon: "message.fill", label: "Mesaj") {
                        open("sms://\(digits)")
                    }
                    GlassActionButton(icon: "video.fill", label: "FaceTime") {
                        open("facetime://\(digits)")
                    }
                }
                GlassActionButton(icon: "person.crop.circle.badge.plus", label: "Salvează") {
                    saving = p
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 4)
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { UIApplication.shared.open(u) }
    }
}

// MARK: - System "add to Contacts" flow (CNContactViewController, unknown contact)

private struct SystemContactSaveSheet: UIViewControllerRepresentable {
    let payload: SharedContactPayload

    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        let parts = payload.name.split(separator: " ", maxSplits: 1).map(String.init)
        contact.givenName = parts.first ?? payload.name
        if parts.count > 1 { contact.familyName = parts[1] }
        contact.phoneNumbers = payload.phones.map {
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
        }
        contact.emailAddresses = payload.emails.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }
        if let img = payload.avatarImage { contact.imageData = img.jpegData(compressionQuality: 0.9) }

        let vc = CNContactViewController(forUnknownContact: contact)
        vc.contactStore = CNContactStore()
        vc.allowsActions = false
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}
