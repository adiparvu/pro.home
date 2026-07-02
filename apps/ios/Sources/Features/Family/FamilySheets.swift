import SwiftUI

// MARK: - Constants

let kRoles = ["owner", "partner", "child", "member", "tenant", "guest"]
let kRoleLabels: [String: String] = [
    "owner": "Owner", "partner": "Partner", "child": "Child",
    "member": "Member", "tenant": "Tenant", "guest": "Guest"
]
let kRoleIcons: [String: String] = [
    "owner": "house.fill", "partner": "heart.fill", "child": "figure.child",
    "member": "person.fill", "tenant": "key.fill", "guest": "person.badge.clock"
]
let kColors = ["#5B8AF5", "#FF6B6B", "#51CF66", "#FF9F43", "#A29BFE", "#FD79A8", "#00CEC9", "#FDCB6E"]
let kSocialPlatforms = ["instagram", "facebook", "whatsapp", "linkedin", "tiktok", "twitter"]

// MARK: - Add sheet

struct AddFamilyMemberSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss
    let propertyId: UUID?
    var propertyName: String? = nil
    var preselectedRole: String? = nil

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var showBirthday = false
    @State private var birthday = Date()
    @State private var role = "member"
    @State private var color = "#5B8AF5"
    @State private var socialLinks: [SocialLink] = []
    @State private var sendInvite = true
    @State private var isSaving = false
    @State private var showAddSocial = false

    private var fullName: String {
        [firstName.trimmingCharacters(in: .whitespaces),
         lastName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    private var canSave: Bool { !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        avatarPreview
                        colorRow
                        fieldsSection
                        roleSection
                        socialLinksSection
                        if !email.isEmpty {
                            inviteSection
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Add Member").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.accentColor) }
                        else { Text("Add").font(AppFont.subheadline).foregroundStyle(canSave ? .blue : Color.primary.opacity(0.3)) }
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showAddSocial) {
                AddSocialLinkSheet { link in socialLinks.append(link) }
            }
        }
        .onAppear {
            if let preset = preselectedRole { role = preset }
        }
    }

    private var avatarPreview: some View {
        ZStack {
            Circle().fill((Color(hex: color) ?? .blue).opacity(0.22))
                .overlay(Circle().strokeBorder((Color(hex: color) ?? .blue).opacity(0.5), lineWidth: 2))
            Text(fullName.isEmpty ? "?" : String(fullName.prefix(2)).uppercased())
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: color) ?? .blue)
        }
        .frame(width: 80, height: 80)
        .padding(.top, AppSpacing.sm)
    }

    private var colorRow: some View {
        HStack(spacing: 10) {
            ForEach(kColors, id: \.self) { c in
                Button { color = c } label: {
                    Circle().fill(Color(hex: c) ?? .blue)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white, lineWidth: color == c ? 2 : 0))
                        .scaleEffect(color == c ? 1.15 : 1.0)
                        .animation(.spring(response: 0.2), value: color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fieldsSection: some View {
        VStack(spacing: 0) {
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
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
    }

    private var birthdayRow: some View {
        VStack(spacing: 0) {
            Button { withAnimation { showBirthday.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gift.fill").font(.system(size: 14)).foregroundStyle(.pink).frame(width: 28)
                    Text(showBirthday ? formatted(birthday) : "Date of birth")
                        .font(.system(size: 15))
                        .foregroundStyle(showBirthday ? .primary : Color.primary.opacity(AppOpacity.secondaryText))
                    Spacer()
                    Image(systemName: showBirthday ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            if showBirthday {
                DatePicker("", selection: $birthday, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.horizontal, AppSpacing.sm).padding(.bottom, AppSpacing.sm)
            }
        }
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROLE").font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).padding(.leading, AppSpacing.xxs)
            HStack(spacing: 12) {
                ColoredIconBadge(icon: kRoleIcons[role] ?? "person.fill", color: .blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(kRoleLabels[role] ?? role.capitalized))
                        .font(AppFont.subheadline).foregroundStyle(.primary)
                    if role == "tenant" {
                        Text("Limited access — tasks and chat")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }
                Spacer()
                Picker("Role", selection: $role) {
                    ForEach(kRoles, id: \.self) { r in
                        Label(LocalizedStringKey(kRoleLabels[r] ?? r.capitalized), systemImage: kRoleIcons[r] ?? "person.fill").tag(r)
                    }
                }
                .pickerStyle(.menu)
                .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private var socialLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOCIAL NETWORKS").font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).padding(.leading, AppSpacing.xxs)
            VStack(spacing: 0) {
                ForEach(Array(socialLinks.enumerated()), id: \.element.id) { idx, link in
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: link.platformIcon, color: link.platformColor, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LocalizedStringKey(link.platformLabel)).font(AppFont.captionEmphasis).foregroundStyle(.primary)
                            TextField("@\(link.handle)", text: Binding(
                                get: { socialLinks[idx].handle },
                                set: { socialLinks[idx].handle = $0 }
                            ))
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
                        }
                        Spacer()
                        Button { socialLinks.remove(at: idx) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(.red.opacity(0.8))
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
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Color.accentColor)
                        Text("Add social network").font(.system(size: 14)).foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                }
                .buttonStyle(.plain)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INVITATION").font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).padding(.leading, AppSpacing.xxs)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "envelope.badge.fill", color: .blue, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send invitation").font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                        Text("The person will receive an invitation email").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                    Spacer()
                    Toggle("", isOn: $sendInvite).labelsHidden().tint(.accentColor)
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private func fieldRow(icon: String, color: Color, placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default, autocap: TextInputAutocapitalization = .words) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(width: 28)
            TextField(placeholder, text: text)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
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

    private func parseBirthday(_ s: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: s)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let name = fullName
        let bdString = birthdayString()
        do {
            try await familyService.add(
                name: name, role: role,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                color: color, propertyId: propertyId,
                birthday: bdString, socialLinks: socialLinks
            )
            if let bdStr = bdString, let bdDate = parseBirthday(bdStr) {
                await familyService.addBirthdayToCalendar(name: name, birthday: bdDate)
            }
            if sendInvite, !email.isEmpty {
                sendInviteEmail(to: email, name: name)
            }
        } catch {
            #if DEBUG
            print("[FamilySheets] save error: \(error)")
            #endif
        }
        HapticFeedback.success()
        dismiss()
    }

    private func sendInviteEmail(to email: String, name: String) {
        Task {
            await familyService.sendInvite(to: email, name: name, role: role,
                                           propertyId: propertyId, propertyName: propertyName)
        }
    }
}

// MARK: - Add Social Link sheet

struct AddSocialLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (SocialLink) -> Void

    @State private var platform = "instagram"
    @State private var handle = ""

    private var link: SocialLink { SocialLink(platform: platform, handle: handle) }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        ForEach(kSocialPlatforms, id: \.self) { p in
                            let sl = SocialLink(platform: p, handle: "")
                            Button { platform = p } label: {
                                VStack(spacing: 6) {
                                    ColoredIconBadge(icon: sl.platformIcon, color: sl.platformColor, size: 48)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .strokeBorder(platform == p ? sl.platformColor : .clear, lineWidth: 2)
                                        )
                                    Text(LocalizedStringKey(sl.platformLabel))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(platform == p ? sl.platformColor : Color.primary.opacity(0.4))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)

                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: link.platformIcon, color: link.platformColor, size: 36)
                        TextField("@username", text: $handle)
                            .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                    .padding(.horizontal, AppSpacing.xl)

                    Spacer()
                }
            }
            .navigationTitle("Add Network").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let h = handle.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
                        guard !h.isEmpty else { return }
                        onAdd(SocialLink(platform: platform, handle: h))
                        dismiss()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(handle.isEmpty ? Color.primary.opacity(0.3) : .blue)
                    .disabled(handle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
