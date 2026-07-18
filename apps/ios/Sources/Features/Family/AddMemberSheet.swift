import SwiftUI
import ContactsUI
import PhotosUI

// MARK: - Add member (rebuilt)
//
// Apple-Contacts-like: ONE scroll, four moments —
//   1. IDENTITY  — big initials avatar + intentional colour choice + name.
//   2. CONTACT   — e-mail/phone with live validation; the e-mail drives the
//                  invitation, and says so the moment it becomes valid.
//   3. ROLE      — the consequential choice, promoted from a dropdown to
//                  large honest cards (family / tenant / worker / guest),
//                  each with one true sentence of what that role sees.
//   4. MORE      — collapsed extras: birthday (for the calendar) + socials.
//
// Saving mirrors the tenant form's ATOMIC pipeline: validate before creating
// anything, insert the member, then send the invite — and if the invite
// fails, roll the member back so nothing half-added lingers in members or
// chat. Every failure is surfaced; nothing is fire-and-forget.
//
// The type keeps the old name and initializer so all existing call sites
// (FamilyView, MembersHubView, ChatView, ConversationsView) are untouched.

struct AddFamilyMemberSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let propertyId: UUID?
    var propertyName: String? = nil
    var preselectedRole: String? = nil

    // Identity
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var color = kColors[0]
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: UIImage?

    // Contact
    @State private var email = ""
    @State private var phone = ""
    @State private var sendInvite = true

    // Role
    @State private var roleCard: MemberRoleCard = .family
    @State private var familyVariant = "member"
    @State private var showRoleInfo = false

    // Contacts import
    @State private var showContactPicker = false

    // More (collapsed by default)
    @State private var showMore = false
    @State private var includeBirthday = false
    @State private var birthday = Date()
    @State private var socialLinks: [SocialLink] = []
    @State private var showAddSocial = false

    // Save
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Derived state

    private var trimmedFirstName: String { firstName.trimmingCharacters(in: .whitespaces) }
    private var fullName: String {
        [trimmedFirstName, lastName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    private var emailIsValid: Bool {
        // One shared authority (EmailFormat) with the tenant and edit flows.
        EmailFormat.isValid(trimmedEmail)
    }
    /// Empty is fine (e-mail is optional); non-empty must look like an address.
    private var emailFieldOK: Bool { trimmedEmail.isEmpty || emailIsValid }

    private var phoneIsValid: Bool {
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        return trimmed.unicodeScalars.allSatisfy(allowed.contains)
            && trimmed.filter(\.isNumber).count >= 5
    }
    private var phoneFieldOK: Bool { phone.trimmingCharacters(in: .whitespaces).isEmpty || phoneIsValid }

    /// The raw role string persisted to `family_members.role`.
    private var role: String { roleCard == .family ? familyVariant : roleCard.rawValue }

    private var canSave: Bool {
        !trimmedFirstName.isEmpty && emailFieldOK && phoneFieldOK && !isSaving
    }

    private var selectSpring: Animation? { reduceMotion ? nil : .snappy(duration: 0.28) }
    private var revealAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xl) {
                    identitySection
                    contactSection
                    roleSection
                    moreSection
                    Spacer(minLength: AppSpacing.sm)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { addButton }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
            }
            .sheet(isPresented: $showAddSocial) {
                AddSocialLinkSheet { link in socialLinks.append(link) }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await handlePhotoPick(newItem) }
            }
            .sheet(isPresented: $showContactPicker) {
                MemberContactPicker { picked in
                    applyImportedContact(picked)
                    showContactPicker = false
                } onCancel: {
                    showContactPicker = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showRoleInfo) {
                RolePermissionsSheet(highlighted: role)
            }
            .alert("Couldn't add the member", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
        .onAppear(perform: applyPreselectedRole)
    }

    private func applyPreselectedRole() {
        switch preselectedRole {
        case "partner", "member", "teen", "child":
            roleCard = .family
            familyVariant = preselectedRole ?? "member"
        case "owner":
            // An extra owner is never added from this form; treat as adult.
            roleCard = .family
            familyVariant = "member"
        case "tenant": roleCard = .tenant
        case "worker": roleCard = .worker
        case "guest":  roleCard = .guest
        default: break
        }
    }

    // MARK: 1. Identity

    private var identitySection: some View {
        VStack(spacing: AppSpacing.base) {
            avatar
            colorPicker
            FormGroup {
                FormRow(icon: "person.fill", tint: .blue) {
                    TextField("First name *", text: $firstName)
                        .font(AppFont.scaled(15)).tint(.accentColor)
                        .textInputAutocapitalization(.words)
                        .textContentType(.givenName)
                }
                FormDivider()
                FormRow(icon: "person", tint: Color.primary.opacity(AppOpacity.disabled)) {
                    TextField("Last name", text: $lastName)
                        .font(AppFont.scaled(15)).tint(.accentColor)
                        .textInputAutocapitalization(.words)
                        .textContentType(.familyName)
                }
            }
            importFromContactsButton
        }
    }

    /// One tap into the system contact picker; the selection pre-fills the
    /// name and contact fields (the user still reviews before saving).
    private var importFromContactsButton: some View {
        Button {
            HapticFeedback.impact(.light)
            showContactPicker = true
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(AppFont.captionEmphasis)
                Text("mem_import_contacts")
                    .font(AppFont.captionEmphasis)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Fills the form from a picked address-book card. Only non-empty fields
    /// overwrite, so importing a phone-only contact never wipes a typed e-mail.
    private func applyImportedContact(_ contact: ImportedContact) {
        withAnimation(revealAnimation) {
            if !contact.firstName.isEmpty { firstName = contact.firstName }
            if !contact.lastName.isEmpty { lastName = contact.lastName }
            if let mail = contact.email, !mail.isEmpty { email = mail }
            if let tel = contact.phone, !tel.isEmpty { phone = tel }
        }
        HapticFeedback.success()
    }

    private var avatarColor: Color { Color(hex: color) ?? .blue }

    /// Tapping the avatar opens the photo library; the picked photo previews
    /// instantly and uploads once the member row exists (in `save()`).
    private var avatar: some View {
        VStack(spacing: AppSpacing.sm) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                avatarCircle
            }
            .buttonStyle(.plain)
            .accessibilityLabel(avatarImage == nil ? Text("Add photo") : Text("Change photo"))
            if avatarImage != nil {
                Button {
                    HapticFeedback.impact(.light)
                    withAnimation(revealAnimation) {
                        avatarImage = nil
                        selectedPhoto = nil
                    }
                } label: {
                    Text("Remove photo")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.brandDanger.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var avatarCircle: some View {
        ZStack {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable().scaledToFill()
            } else {
                Circle().fill(avatarColor.opacity(0.22))
                    .overlay(Circle().strokeBorder(avatarColor.opacity(0.5), lineWidth: 2))
                if fullName.isEmpty {
                    Image(systemName: "person.fill")
                        .font(AppFont.scaled(34, weight: .semibold))
                        .foregroundStyle(avatarColor.opacity(0.8))
                } else {
                    Text(String(fullName.prefix(2)).uppercased())
                        .font(AppFont.scaled(30, weight: .bold, design: .rounded))
                        .foregroundStyle(avatarColor)
                        .contentTransition(.opacity)
                }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(AppFont.scaled(10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
        }
        .animation(revealAnimation, value: color)
    }

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        withAnimation(revealAnimation) { avatarImage = image }
        HapticFeedback.success()
    }

    /// The avatar's colour, presented as a deliberate choice right under it —
    /// the ring and spring make the selection legible instead of decorative.
    private var colorPicker: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(Array(kColors.enumerated()), id: \.element) { idx, c in
                let selected = color == c
                Button {
                    HapticFeedback.selection()
                    withAnimation(selectSpring) { color = c }
                } label: {
                    Circle().fill(Color(hex: c) ?? .blue)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().strokeBorder(.white, lineWidth: selected ? 2 : 0)
                        )
                        .background(
                            Circle().strokeBorder((Color(hex: c) ?? .blue).opacity(selected ? 0.55 : 0),
                                                  lineWidth: 2)
                                .padding(-4)
                        )
                        .scaleEffect(selected ? 1.12 : 1.0)
                        .padding(AppSpacing.xxs)
                        .contentShape(Circle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Avatar color"))
                .accessibilityValue(Text(verbatim: "\(idx + 1)/\(kColors.count)"))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
        .background(Color.subtleFill.opacity(0.6), in: Capsule())
    }

    // MARK: 2. Contact

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormGroup(title: "CONTACT") {
                FormRow(icon: "envelope.fill", tint: .orange) {
                    TextField("E-mail", text: $email)
                        .font(AppFont.scaled(15)).tint(.accentColor)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                }
                FormDivider()
                FormRow(icon: "phone.fill", tint: Color.brandSuccess) {
                    TextField("Phone", text: $phone)
                        .font(AppFont.scaled(15)).tint(.accentColor)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                if emailIsValid {
                    FormDivider()
                    FormRow(icon: "envelope.badge.fill", tint: .accentColor) {
                        Toggle(isOn: $sendInvite) {
                            Text("Send invitation")
                                .font(AppFont.scaled(15))
                        }
                        .tint(.accentColor)
                    }
                }
            }
            contactFootnotes
        }
        .animation(revealAnimation, value: emailIsValid)
        .animation(revealAnimation, value: emailFieldOK)
        .animation(revealAnimation, value: phoneFieldOK)
        .animation(revealAnimation, value: sendInvite)
    }

    @ViewBuilder
    private var contactFootnotes: some View {
        // Inline, honest, and only when there's something to say.
        if !emailFieldOK {
            footnote("This e-mail address doesn't look valid",
                     icon: "exclamationmark.circle.fill", tint: Color.brandDanger)
        }
        if !phoneFieldOK {
            footnote("The phone number can contain only digits, spaces and +",
                     icon: "exclamationmark.circle.fill", tint: Color.brandDanger)
        }
        if emailIsValid, sendInvite {
            footnote("The person will receive an invitation email",
                     icon: "paperplane.fill", tint: .accentColor)
            footnote("The invitation is valid for 7 days; you can track and resend it from Members → Invitations.",
                     icon: "clock", tint: Color.secondaryTextColor)
        }
    }

    private func footnote(_ text: LocalizedStringKey, icon: String, tint: Color) -> some View {
        Label {
            Text(text)
                .font(AppFont.scaled(11))
                .foregroundStyle(tint == Color.brandDanger ? tint : Color.primary.opacity(AppOpacity.secondaryText))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).font(AppFont.scaled(11)).foregroundStyle(tint)
        }
        .padding(.leading, AppSpacing.xxs)
    }

    // MARK: 3. Role — the centerpiece

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xs) {
                Text("Role")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                Button {
                    HapticFeedback.impact(.light)
                    showRoleInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Roles & permissions")
            }
            .padding(.leading, AppSpacing.xxs)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.md),
                                GridItem(.flexible(), spacing: AppSpacing.md)],
                      spacing: AppSpacing.md) {
                ForEach(MemberRoleCard.allCases) { card in
                    MemberRoleCardView(card: card, isSelected: roleCard == card) {
                        HapticFeedback.selection()
                        withAnimation(selectSpring) { roleCard = card }
                    }
                }
            }

            if roleCard == .family {
                familyVariantPicker
                    .transition(reduceMotion ? .opacity
                                             : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The family card fans out into who exactly: partner, adult, teen or
    /// child — each with the same honest one-liner the permissions sheet uses.
    /// Tags are the exact role strings the backend accepts at invite time
    /// (send-invite-email's mapRole: "partner" → partner, "member" →
    /// family_adult, "teen" → family_teen, "child" → family_child).
    private var familyVariantPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    variantChip("Partner", icon: "heart.fill", tag: "partner")
                    variantChip("Adult", icon: "person.fill", tag: "member")
                    variantChip("Teen", icon: "figure.wave", tag: "teen")
                    variantChip("Child", icon: "figure.child", tag: "child")
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
            if let desc = kRoleDescriptions[familyVariant] {
                Text(LocalizedStringKey(desc))
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .padding(.leading, AppSpacing.xxs)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(familyVariant)
                    .transition(.opacity)
            }
        }
    }

    private func variantChip(_ title: String.LocalizationValue, icon: String, tag: String) -> some View {
        GlassFilterChip(label: String(localized: title),
                        systemImage: icon,
                        isSelected: familyVariant == tag) {
            withAnimation(selectSpring) { familyVariant = tag }
        }
    }

    // MARK: 4. More — birthday + social networks, collapsed by default

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Button {
                HapticFeedback.impact(.light)
                withAnimation(revealAnimation) { showMore.toggle() }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(Color.accentColor)
                    Text("More")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                .background(Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
            .accessibilityAddTraits(showMore ? [.isSelected] : [])

            if showMore {
                Group {
                    birthdayGroup
                    socialLinksGroup
                }
                .transition(reduceMotion ? .opacity
                                         : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var birthdayGroup: some View {
        FormGroup {
            FormRow(icon: "gift.fill", tint: .pink) {
                Toggle(isOn: $includeBirthday.animation(revealAnimation)) {
                    Text("Date of birth").font(AppFont.scaled(15))
                }
                .tint(.accentColor)
            }
            if includeBirthday {
                FormDivider()
                DatePicker("Date of birth", selection: $birthday,
                           in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(AppFont.scaled(15))
                    .tint(.accentColor)
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.sm)
            }
        }
    }

    private var socialLinksGroup: some View {
        FormGroup(title: "SOCIAL NETWORKS") {
            ForEach(Array(socialLinks.enumerated()), id: \.element.id) { idx, link in
                HStack(spacing: AppSpacing.md) {
                    SocialBrandIcon(platform: link.platform, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LocalizedStringKey(link.platformLabel))
                            .font(AppFont.captionEmphasis).foregroundStyle(.primary)
                        TextField("@username", text: Binding(
                            get: { socialLinks.indices.contains(idx) ? socialLinks[idx].handle : "" },
                            set: { if socialLinks.indices.contains(idx) { socialLinks[idx].handle = $0 } }
                        ))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    }
                    Spacer()
                    Button {
                        HapticFeedback.impact(.light)
                        withAnimation(revealAnimation) { socialLinks.remove(at: idx) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(AppFont.scaled(18))
                            .foregroundStyle(Color.brandDanger.opacity(0.85))
                    }
                    .accessibilityLabel(Text("Remove") + Text(verbatim: " \(link.platformLabel)"))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm + 2)
                FormDivider()
            }
            Button {
                HapticFeedback.impact(.light)
                showAddSocial = true
            } label: {
                HStack(spacing: AppSpacing.sm + 2) {
                    Image(systemName: "plus.circle.fill")
                        .font(AppFont.scaled(20)).foregroundStyle(Color.accentColor)
                    Text("Add social network")
                        .font(AppFont.scaled(14)).foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Primary CTA

    private var addButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            Task { await save() }
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Add member").font(AppFont.headline)
                }
            }
            .foregroundStyle(canSave ? Color.white : Color.primary.opacity(AppOpacity.disabled))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(canSave ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(Color.primary.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .animation(revealAnimation, value: canSave)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm).padding(.bottom, AppSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: Save — atomic add + invite + rollback

    private func save() async {
        // Everything is validated BEFORE anything is created: an invite to a
        // bad address would fail after the member row exists, leaving a
        // half-added member (the CTA is disabled in those states anyway).
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        let name = fullName
        let birthdayString = includeBirthday ? AppDate.dayString(from: birthday) : nil
        let cleanedLinks = socialLinks.filter {
            !$0.handle.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let member: FamilyMember
        do {
            guard let inserted = try await familyService.add(
                name: name, role: role,
                email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                phone: phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone.trimmingCharacters(in: .whitespaces),
                color: color, propertyId: propertyId,
                birthday: birthdayString, socialLinks: cleanedLinks
            ) else {
                errorMessage = String(localized: "You need to be signed in to add a member.")
                HapticFeedback.warning()
                return
            }
            member = inserted
        } catch {
            // Surface the failure — a silently-dismissed form is how
            // "adding doesn't work" bugs are born.
            errorMessage = error.localizedDescription
            HapticFeedback.warning()
            return
        }

        if sendInvite, emailIsValid {
            if let err = await familyService.sendInvite(
                to: trimmedEmail, name: name, role: role,
                propertyId: propertyId, propertyName: propertyName) {
                // Atomic add: a failed invite rolls the member back so
                // nothing half-added lingers in members or chat.
                await familyService.delete(member)
                errorMessage = String(localized: "The member was not added because the invitation failed:") + " " + err
                HapticFeedback.warning()
                return
            }
        }

        // Side effects only after the pipeline fully succeeded, so a rollback
        // never leaves a stray photo or recurring calendar event behind. The
        // photo is cosmetic: a failed upload must not undo a successful add,
        // so it's best-effort — FamilyService.error surfaces the failure.
        if let avatarImage {
            _ = await familyService.uploadAvatar(for: member, image: avatarImage)
        }
        if includeBirthday {
            await familyService.addBirthdayToCalendar(name: name, birthday: birthday)
        }
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - Role cards

/// The four choices the form offers. Owner is deliberately absent — a home
/// already has one, and partners are added through the Family card.
private enum MemberRoleCard: String, CaseIterable, Identifiable {
    case family, tenant, worker, guest
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .family: return "Family"
        case .tenant: return "Tenant"
        case .worker: return "Worker"
        case .guest:  return "Guest"
        }
    }

    /// One honest sentence per role, aligned with the real family-vs-outsider
    /// model (`PropertyRole.isFamilyMember`) and the permissions sheet:
    /// family shares the household; outsiders keep strictly their own things.
    var blurb: LocalizedStringKey {
        switch self {
        case .family: return "Lives here — shares the home, tasks, finances and chat"
        case .tenant: return "Sees own tasks and shared bills"
        case .worker: return "Sees only assigned tasks and chat"
        case .guest:  return "Chat only — nothing from the home"
        }
    }

    var icon: String {
        switch self {
        case .family: return "figure.2.and.child.holdinghands"
        case .tenant: return "key.fill"
        case .worker: return "hammer.fill"
        case .guest:  return "person.badge.clock"
        }
    }

    var tint: Color {
        switch self {
        case .family: return Color.brandPurple
        case .tenant: return Color.brandWarning
        case .worker: return Color.brandTeal
        case .guest:  return Color.brandSkyBlue
        }
    }
}

// MARK: - Contacts import (system picker bridge)

/// The fields lifted off a picked address-book card.
struct ImportedContact {
    let firstName: String
    let lastName: String
    let email: String?
    let phone: String?
}

/// System contact picker (CNContactPickerViewController) that hands back the
/// structured fields the add-member form needs. The chat's ChatContactPicker
/// returns a pre-formatted "name | phone" string for message composition, so
/// this form needs its own bridge to keep first/last name and e-mail intact.
/// The picker runs out-of-process — no Contacts permission prompt.
struct MemberContactPicker: UIViewControllerRepresentable {
    let onPick: (ImportedContact) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: MemberContactPicker
        init(_ parent: MemberContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onPick(ImportedContact(
                firstName: contact.givenName.trimmingCharacters(in: .whitespaces),
                lastName: contact.familyName.trimmingCharacters(in: .whitespaces),
                email: (contact.emailAddresses.first?.value as String?)?
                    .trimmingCharacters(in: .whitespaces),
                phone: contact.phoneNumbers.first?.value.stringValue
                    .trimmingCharacters(in: .whitespaces)
            ))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onCancel()
        }
    }
}

private struct MemberRoleCardView: View {
    let card: MemberRoleCard
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Image(systemName: card.icon)
                        .font(AppFont.scaled(19, weight: .semibold))
                        .foregroundStyle(isSelected ? card.tint : Color.primary.opacity(AppOpacity.mediumText))
                        .frame(height: 24)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(17))
                        .foregroundStyle(Color.accentColor)
                        .opacity(isSelected ? 1 : 0)
                        .scaleEffect(isSelected ? 1 : 0.5)
                }
                Text(card.title)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text(card.blurb)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.08))
                           : AnyShapeStyle(Color.primary.opacity(0.04)),
                in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor
                                             : Color.primary.opacity(AppOpacity.subtleFill),
                                  lineWidth: isSelected ? 1.6 : 0.5)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(card.title))
        .accessibilityHint(Text(card.blurb))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
