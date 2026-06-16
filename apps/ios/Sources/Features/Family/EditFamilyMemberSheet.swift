import SwiftUI

// MARK: - Edit sheet

struct EditFamilyMemberSheet: View {
    @EnvironmentObject private var familyService: FamilyService
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
    }

    private var fullName: String {
        [firstName.trimmingCharacters(in: .whitespaces),
         lastName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

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
                        deleteButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Edit Member").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.accentColor) }
                        else { Text("Save").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor) }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .confirmationDialog("Remove \(member.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task { await familyService.delete(member); dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAddSocial) {
                AddSocialLinkSheet { link in socialLinks.append(link) }
            }
        }
    }

    private var avatarPreview: some View {
        ZStack {
            Circle().fill((Color(hex: color) ?? .blue).opacity(0.22))
                .overlay(Circle().strokeBorder((Color(hex: color) ?? .blue).opacity(0.5), lineWidth: 2))
            Text(fullName.isEmpty ? "?" : String(fullName.prefix(2)).uppercased())
                .font(.system(size: 28, weight: .bold)).foregroundStyle(Color(hex: color) ?? .blue)
        }
        .frame(width: 80, height: 80).padding(.top, 8)
    }

    private var colorRow: some View {
        HStack(spacing: 10) {
            ForEach(kColors, id: \.self) { c in
                Button { color = c } label: {
                    Circle().fill(Color(hex: c) ?? .blue).frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(.white, lineWidth: color == c ? 2 : 0))
                        .scaleEffect(color == c ? 1.15 : 1.0).animation(.spring(response: 0.2), value: color)
                }.buttonStyle(.plain)
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
            fieldRow(icon: "phone.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4), placeholder: "Phone", text: $phone, keyboard: .phonePad)
            div
            birthdayRow
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private var birthdayRow: some View {
        VStack(spacing: 0) {
            Button { withAnimation { showBirthday.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gift.fill").font(.system(size: 14)).foregroundStyle(.pink).frame(width: 28)
                    Text(showBirthday ? formatted(birthday) : "Date of birth")
                        .font(.system(size: 15))
                        .foregroundStyle(showBirthday ? .primary : Color.primary.opacity(0.45))
                    Spacer()
                    Image(systemName: showBirthday ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            if showBirthday {
                DatePicker("", selection: $birthday, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROLE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
            HStack(spacing: 12) {
                ColoredIconBadge(icon: kRoleIcons[role] ?? "person.fill", color: .blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kRoleLabels[role] ?? role.capitalized)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    if role == "tenant" {
                        Text("Limited access — tasks and chat")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                Spacer()
                Picker("Role", selection: $role) {
                    ForEach(kRoles, id: \.self) { r in
                        Label(kRoleLabels[r] ?? r.capitalized, systemImage: kRoleIcons[r] ?? "person.fill").tag(r)
                    }
                }
                .pickerStyle(.menu).tint(.accentColor)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private var socialLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SOCIAL NETWORKS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(socialLinks.enumerated()), id: \.element.id) { idx, link in
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: link.platformIcon, color: link.platformColor, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.platformLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                            TextField("@username", text: Binding(
                                get: { socialLinks[idx].handle },
                                set: { socialLinks[idx].handle = $0 }
                            ))
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        }
                        Spacer()
                        Button { socialLinks.remove(at: idx) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
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
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Label("Remove member", systemImage: "trash")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.red)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func fieldRow(icon: String, color: Color, placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default, autocap: TextInputAutocapitalization = .words) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(width: 28)
            TextField(placeholder, text: text)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(keyboard).textInputAutocapitalization(autocap)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }

    private func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMMM yyyy"
        fmt.locale = Locale(identifier: "en_US")
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
        await familyService.update(updated)
        HapticFeedback.success()
        dismiss()
    }
}
