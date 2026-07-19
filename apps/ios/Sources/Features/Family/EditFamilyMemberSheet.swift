import SwiftUI
import PhotosUI

// MARK: - Edit sheet

struct EditFamilyMemberSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss
    var member: FamilyMember

    @State private var firstName: String
    @State private var lastName: String
    @State private var email: String
    @State private var phone: String
    @State private var showBirthday: Bool
    @State private var birthday: Date
    @State private var role: String
    @State private var color: String
    @State private var socialLinks: [SocialLink]
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var showAddSocial = false
    @State private var saveError: String?

    // Photo (roster-only members — account holders' photos come from their
    // live profile via MemberDirectory, so they're not editable from here).
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var avatarUrl: String?
    @State private var isUploadingPhoto = false

    init(member: FamilyMember) {
        self.member = member
        let parts = member.name.split(separator: " ", maxSplits: 1)
        _firstName = State(initialValue: parts.count > 0 ? String(parts[0]) : member.name)
        _lastName  = State(initialValue: parts.count > 1 ? String(parts[1]) : "")
        _email     = State(initialValue: member.email ?? "")
        _phone     = State(initialValue: member.phone ?? "")
        let bd = member.birthdayDate
        _showBirthday = State(initialValue: bd != nil)
        _birthday  = State(initialValue: bd ?? Date())
        _role      = State(initialValue: member.role)
        _color     = State(initialValue: member.color)
        _socialLinks = State(initialValue: member.socialLinks ?? [])
        _avatarUrl = State(initialValue: member.avatarUrl)
    }

    private var fullName: String {
        [firstName.trimmingCharacters(in: .whitespaces),
         lastName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        FormScaffold(title: "Edit Member",
                     canSave: !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
                     isSaving: isSaving,
                     error: $saveError,
                     onSave: { Task { await save() } }) {
            avatarPreview
            fieldsSection
            roleSection
            socialLinksSection
            deleteButton
        }
        .scrollDismissesKeyboard(.immediately)
        .confirmationDialog("Remove \(member.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task { await familyService.delete(member); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddSocial) {
            AddSocialLinkSheet { link in socialLinks.append(link) }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhotoPick(newItem) }
        }
    }

    // MARK: Photo

    /// Roster-only members carry their photo on the `family_members` row;
    /// account holders always show their live profile photo, so offering a
    /// picker here would set a URL that never renders.
    private var canEditPhoto: Bool { member.userId == nil }

    private var hasPhoto: Bool {
        previewImage != nil || !(avatarUrl ?? "").isEmpty
    }

    /// The freshest row (avatar ops update `familyService.members`), so a
    /// second upload in the same session cleans up the first file.
    private var freshMember: FamilyMember {
        familyService.members.first { $0.id == member.id } ?? member
    }

    @ViewBuilder
    private var avatarPreview: some View {
        VStack(spacing: AppSpacing.sm) {
            if canEditPhoto {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    avatarCircle
                }
                .buttonStyle(.plain)
                .disabled(isUploadingPhoto)
                .accessibilityLabel(hasPhoto ? Text("Change photo") : Text("Add photo"))
                if hasPhoto {
                    Button {
                        HapticFeedback.impact(.light)
                        Task { await removePhoto() }
                    } label: {
                        Text("Remove photo")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.brandDanger.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingPhoto)
                }
            } else {
                avatarCircle
            }
        }
        .padding(.top, AppSpacing.sm)
    }

    private var avatarCircle: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable().scaledToFill()
            } else if let avatarUrl, !avatarUrl.isEmpty {
                StorageImage(source: avatarUrl) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { initialsCircle }
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if canEditPhoto {
                Image(systemName: "camera.fill")
                    .font(AppFont.scaled(10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            }
        }
        .overlay {
            if isUploadingPhoto {
                Circle().fill(.black.opacity(0.35))
                ProgressView().tint(.white)
            }
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill((Color(hex: color) ?? .blue).opacity(0.22))
                .overlay(Circle().strokeBorder((Color(hex: color) ?? .blue).opacity(0.5), lineWidth: 2))
            Text(fullName.isEmpty ? "?" : String(fullName.prefix(2)).uppercased())
                .font(AppFont.scaled(28, weight: .bold)).foregroundStyle(Color(hex: color) ?? .blue)
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        previewImage = image  // instant preview while the upload runs
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        if let updated = await familyService.uploadAvatar(for: freshMember, image: image) {
            avatarUrl = updated.avatarUrl
            HapticFeedback.success()
        } else {
            previewImage = nil
            surfacePhotoError()
        }
    }

    private func removePhoto() async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        if let updated = await familyService.removeAvatar(for: freshMember) {
            previewImage = nil
            avatarUrl = updated.avatarUrl
            HapticFeedback.success()
        } else {
            surfacePhotoError()
        }
    }

    /// Shows the failure in THIS sheet's banner and clears the service copy,
    /// so FamilyView's global alert doesn't fire a second time behind us.
    private func surfacePhotoError() {
        saveError = familyService.error ?? String(localized: "Couldn't save changes.")
        familyService.error = nil
        HapticFeedback.warning()
    }

    // The colour swatch row is gone (IMG_8664): the member's colour is set
    // once at add time and stays a stable identity — editing keeps it as-is.

    private var fieldsSection: some View {
        FormGroup {
            fieldRow(icon: "person.fill", color: .blue, placeholder: "First name *", text: $firstName)
            div
            fieldRow(icon: "person.fill", color: Color.primary.opacity(0.4), placeholder: "Last name", text: $lastName)
            div
            fieldRow(icon: "envelope.fill", color: .orange, placeholder: "E-mail", text: $email, keyboard: .emailAddress, autocap: .never)
            div
            fieldRow(icon: "phone.fill", color: Color.brandSuccess, placeholder: "Phone", text: $phone, keyboard: .phonePad)
            div
            birthdayRow
        }
    }

    private var birthdayRow: some View {
        VStack(spacing: 0) {
            Button { withAnimation(AppMotion.state) { showBirthday.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gift.fill").font(AppFont.scaled(14)).foregroundStyle(.pink).frame(width: 28)
                    Text(showBirthday ? formatted(birthday) : "Date of birth")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(showBirthday ? .primary : Color.primary.opacity(AppOpacity.secondaryText))
                    Spacer()
                    Image(systemName: showBirthday ? "chevron.up" : "chevron.down")
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            if showBirthday {
                DatePicker("", selection: $birthday, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .padding(.horizontal, AppSpacing.sm).padding(.bottom, AppSpacing.sm)
            }
        }
    }

    private var roleSection: some View {
        FormGroup(title: "ROLE") {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: kRoleIcons[role] ?? "person.fill", color: .blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(kRoleLabels[role] ?? role.capitalized))
                        .font(AppFont.subheadline).foregroundStyle(.primary)
                    if role == "tenant" {
                        Text("Limited access — tasks and chat")
                            .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }
                Spacer()
                Picker("Role", selection: $role) {
                    ForEach(kRoles, id: \.self) { r in
                        Label(LocalizedStringKey(kRoleLabels[r] ?? r.capitalized), systemImage: kRoleIcons[r] ?? "person.fill").tag(r)
                    }
                }
                .pickerStyle(.menu).tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
        }
    }

    private var socialLinksSection: some View {
        FormGroup(title: "SOCIAL NETWORKS") {
            ForEach(Array(socialLinks.enumerated()), id: \.element.id) { idx, link in
                HStack(spacing: 12) {
                    SocialBrandIcon(platform: link.platform, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LocalizedStringKey(link.platformLabel)).font(AppFont.captionEmphasis).foregroundStyle(.primary)
                        TextField("@username", text: Binding(
                            get: { socialLinks[idx].handle },
                            set: { socialLinks[idx].handle = $0 }
                        ))
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.6))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    Spacer()
                    Button { socialLinks.remove(at: idx) } label: {
                        Image(systemName: "minus.circle.fill").font(AppFont.scaled(18)).foregroundStyle(.red.opacity(0.8))
                    }
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
                if idx < socialLinks.count - 1 {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 62)
                }
            }
            Button {
                HapticFeedback.impact(.light)
                showAddSocial = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill").font(AppFont.scaled(20)).foregroundStyle(Color.accentColor)
                    Text("Add social network").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            }
            .buttonStyle(.plain)
        }
    }

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Label("Remove member", systemImage: "trash")
                .font(AppFont.footnote).foregroundStyle(.red)
                .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.base)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }

    private func fieldRow(icon: String, color: Color, placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default, autocap: TextInputAutocapitalization = .words) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(color).frame(width: 28)
            TextField(placeholder, text: text)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(keyboard).textInputAutocapitalization(autocap)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }

    private func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMMM yyyy"
        fmt.locale = .current
        return fmt.string(from: date)
    }

    private func birthdayString() -> String? {
        guard showBirthday else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: birthday)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = member
        updated.name = fullName
        updated.role = role
        updated.email = email.isEmpty ? nil : email
        updated.phone = phone.isEmpty ? nil : phone
        updated.color = color
        updated.birthday = birthdayString()
        updated.socialLinks = socialLinks
        if await familyService.update(updated) {
            HapticFeedback.success()
            dismiss()
        } else {
            saveError = familyService.error ?? String(localized: "Couldn't save changes.")
            HapticFeedback.warning()
        }
    }
}
