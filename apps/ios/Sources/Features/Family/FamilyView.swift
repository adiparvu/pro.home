import SwiftUI

// MARK: - Main view

struct FamilyView: View {
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var propertyService: PropertyService
    @State private var showAdd = false
    @State private var selectedMember: FamilyMember?

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if familyService.isLoading && familyService.members.isEmpty {
                    Spacer(); ProgressView().tint(.white); Spacer()
                } else if familyService.members.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(familyService.members) { member in
                                FamilyMemberRow(member: member)
                                    .onTapGesture { selectedMember = member }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await familyService.delete(member) }
                                        } label: { Label("Elimină", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button { selectedMember = member } label: {
                                            Label("Editează", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 110)
                    }
                }
            }
        }
        .navigationTitle("Familie")
        .navigationBarTitleDisplayMode(.large)
        .floatingSpeedDial(.family)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .task { await familyService.load() }
        .sheet(isPresented: $showAdd) {
            AddFamilyMemberSheet(propertyId: propertyService.primary?.id)
        }
        .sheet(item: $selectedMember) { member in
            MemberProfileSheet(member: member)
        }
        .alert("Eroare", isPresented: Binding(
            get: { familyService.error != nil },
            set: { if !$0 { familyService.error = nil } }
        )) {
            Button("OK") { familyService.error = nil }
        } message: { Text(familyService.error ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.2.fill").font(.system(size: 52)).foregroundStyle(Color.primary.opacity(0.15))
            Text("Niciun membru").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
            Text("Adaugă membrii familiei pentru a colabora pe taskuri și a chata.").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.35)).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Adaugă primul membru") { showAdd = true }.font(.system(size: 14)).foregroundStyle(.blue)
            Spacer()
        }
    }
}

// MARK: - Row

struct FamilyMemberRow: View {
    let member: FamilyMember

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                MemberAvatar(member: member, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(member.roleLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.45))
                        if let bd = member.birthdayDate {
                            let calendar = Calendar.current
                            let comps = calendar.dateComponents([.month, .day], from: bd)
                            if let m = comps.month, let d = comps.day {
                                Text("·").foregroundStyle(Color.primary.opacity(0.2)).font(.system(size: 12))
                                Text("🎂 \(d)/\(m)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    if let phone = member.phone, !phone.isEmpty {
                        quickActionBtn(icon: "phone.fill") {
                            if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    if let email = member.email, !email.isEmpty {
                        quickActionBtn(icon: "envelope.fill") {
                            if let url = URL(string: "mailto:\(email)") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
    }

    private func quickActionBtn(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .glassCircle()
        }
    }
}

// MARK: - Avatar (shared)

struct MemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 38

    var body: some View {
        if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { initials }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Circle().fill(member.swiftColor.opacity(0.25))
                .overlay(Circle().strokeBorder(member.swiftColor.opacity(0.5), lineWidth: 1.5))
            Text(member.initials)
                .font(.system(size: size * 0.33, weight: .bold))
                .foregroundStyle(member.swiftColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Member picker (shared for tasks/chat)

struct MemberPickerView: View {
    @EnvironmentObject private var familyService: FamilyService
    @Binding var selectedIds: [String]
    @Binding var selectedNames: [String]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(familyService.members) { m in
                let selected = selectedIds.contains(m.id.uuidString)
                Button {
                    HapticFeedback.selection()
                    if selected {
                        selectedIds.removeAll { $0 == m.id.uuidString }
                        selectedNames.removeAll { $0 == m.name }
                    } else {
                        selectedIds.append(m.id.uuidString)
                        selectedNames.append(m.name)
                    }
                } label: {
                    HStack(spacing: 12) {
                        MemberAvatar(member: m, size: 36)
                        Text(m.name).font(.system(size: 15)).foregroundStyle(.primary)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(m.swiftColor).font(.system(size: 20))
                        } else {
                            Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.primary.opacity(selected ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Profile preview sheet

struct MemberProfileSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Environment(\.dismiss) private var dismiss
    let member: FamilyMember
    @State private var showEdit = false
    @State private var resolvedMember: FamilyMember

    init(member: FamilyMember) {
        self.member = member
        _resolvedMember = State(initialValue: member)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        profileHeader
                        quickActions
                        if resolvedMember.email != nil || resolvedMember.phone != nil || resolvedMember.birthday != nil {
                            contactSection
                        }
                        if let links = resolvedMember.socialLinks, !links.isEmpty {
                            socialSection(links)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Închide") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Editează") { showEdit = true }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue)
                }
            }
            .sheet(isPresented: $showEdit, onDismiss: {
                if let updated = familyService.members.first(where: { $0.id == member.id }) {
                    resolvedMember = updated
                }
            }) {
                EditFamilyMemberSheet(member: resolvedMember)
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 10) {
            MemberAvatar(member: resolvedMember, size: 80)
            Text(resolvedMember.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
            Text(resolvedMember.roleLabel.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(resolvedMember.swiftColor)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(resolvedMember.swiftColor.opacity(0.12), in: Capsule())
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            if let phone = resolvedMember.phone, !phone.isEmpty {
                profileActionBtn(icon: "phone.fill", label: "Apel", color: Color(red: 0.2, green: 0.8, blue: 0.4)) {
                    if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") { UIApplication.shared.open(url) }
                }
                profileActionBtn(icon: "facetime", label: "FaceTime", color: .blue) {
                    if let url = URL(string: "facetime://\(phone.filter { $0.isNumber })") { UIApplication.shared.open(url) }
                }
                profileActionBtn(icon: "message.badge.filled.fill", label: "WhatsApp", color: Color(red: 0.16, green: 0.72, blue: 0.37)) {
                    let num = phone.filter { $0.isNumber }
                    if let url = URL(string: "https://wa.me/\(num)") { UIApplication.shared.open(url) }
                }
            }
            if let email = resolvedMember.email, !email.isEmpty {
                profileActionBtn(icon: "envelope.fill", label: "Email", color: .orange) {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                }
            }
        }
    }

    private func profileActionBtn(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(0.2), lineWidth: 0.5))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("CONTACT")
            VStack(spacing: 0) {
                if let email = resolvedMember.email, !email.isEmpty {
                    contactRow(icon: "envelope.fill", color: .orange, value: email)
                    if resolvedMember.phone != nil || resolvedMember.birthday != nil {
                        divider
                    }
                }
                if let phone = resolvedMember.phone, !phone.isEmpty {
                    contactRow(icon: "phone.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4), value: phone)
                    if resolvedMember.birthday != nil { divider }
                }
                if let bd = resolvedMember.birthdayDate {
                    contactRow(icon: "gift.fill", color: .pink, value: formatted(bd))
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private func socialSection(_ links: [SocialLink]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("REȚELE SOCIALE")
            VStack(spacing: 0) {
                ForEach(links) { link in
                    Button {
                        if let url = link.openURL { UIApplication.shared.open(url) }
                    } label: {
                        HStack(spacing: 12) {
                            ColoredIconBadge(icon: link.platformIcon, color: link.platformColor, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(link.platformLabel)
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                                Text("@\(link.handle.replacingOccurrences(of: "@", with: ""))")
                                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.3))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    if link.id != links.last?.id { divider }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private func contactRow(icon: String, color: Color, value: String) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color, size: 36)
            Text(value).font(.system(size: 14)).foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 62)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.35))
            .padding(.leading, 4)
    }

    private func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMMM"
        fmt.locale = Locale(identifier: "ro_RO")
        return fmt.string(from: date)
    }
}

// MARK: - Add sheet

private let kRoles = ["owner", "partner", "child", "member", "tenant", "guest"]
private let kRoleLabels: [String: String] = [
    "owner": "Owner", "partner": "Partener", "child": "Copil",
    "member": "Membru", "tenant": "Chiriaș", "guest": "Oaspete"
]
private let kRoleIcons: [String: String] = [
    "owner": "house.fill", "partner": "heart.fill", "child": "figure.child",
    "member": "person.fill", "tenant": "key.fill", "guest": "person.badge.clock"
]
private let kColors = ["#5B8AF5", "#FF6B6B", "#51CF66", "#FF9F43", "#A29BFE", "#FD79A8", "#00CEC9", "#FDCB6E"]
private let kSocialPlatforms = ["instagram", "facebook", "whatsapp", "linkedin", "tiktok", "twitter"]

struct AddFamilyMemberSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Environment(\.dismiss) private var dismiss
    let propertyId: UUID?

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var showBirthday = false
    @State private var birthday = Date()
    @State private var role = "member"
    @State private var color = "#5B8AF5"
    @State private var socialLinks: [SocialLink] = []
    @State private var sendInvite = false
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
                    .padding(.horizontal, 20).padding(.top, 8)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Adaugă Membru").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.blue) }
                        else { Text("Adaugă").font(.system(size: 15, weight: .semibold)).foregroundStyle(canSave ? .blue : Color.primary.opacity(0.3)) }
                    }
                    .disabled(!canSave)
                }
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
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: color) ?? .blue)
        }
        .frame(width: 80, height: 80)
        .padding(.top, 8)
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
            fieldRow(icon: "person.fill", color: .blue, placeholder: "Prenume *", text: $firstName)
            div
            fieldRow(icon: "person.fill", color: Color.primary.opacity(0.4), placeholder: "Nume", text: $lastName)
            div
            fieldRow(icon: "envelope.fill", color: .orange, placeholder: "E-mail", text: $email, keyboard: .emailAddress, autocap: .never)
            div
            fieldRow(icon: "phone.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4), placeholder: "Telefon", text: $phone, keyboard: .phonePad)
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
                    Text(showBirthday ? formatted(birthday) : "Data nașterii")
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
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
    }

    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROL").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
            HStack(spacing: 12) {
                ColoredIconBadge(icon: kRoleIcons[role] ?? "person.fill", color: .blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kRoleLabels[role] ?? role.capitalized)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    if role == "tenant" {
                        Text("Acces limitat — taskuri și chat")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                Spacer()
                Picker("Rol", selection: $role) {
                    ForEach(kRoles, id: \.self) { r in
                        Label(kRoleLabels[r] ?? r.capitalized, systemImage: kRoleIcons[r] ?? "person.fill").tag(r)
                    }
                }
                .pickerStyle(.menu)
                .tint(.blue)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private var socialLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REȚELE SOCIALE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(socialLinks.enumerated()), id: \.element.id) { idx, link in
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: link.platformIcon, color: link.platformColor, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.platformLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
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
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(.blue)
                        Text("Adaugă rețea socială").font(.system(size: 14)).foregroundStyle(.blue)
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

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INVITAȚIE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "envelope.badge.fill", color: .blue, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trimite invitație").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                        Text("Persoana va primi un email de invitație").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                    Spacer()
                    Toggle("", isOn: $sendInvite).labelsHidden().tint(.blue)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private func fieldRow(icon: String, color: Color, placeholder: String, text: Binding<String>,
                          keyboard: UIKeyboardType = .default, autocap: TextInputAutocapitalization = .words) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(color).frame(width: 28)
            TextField(placeholder, text: text)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
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
        fmt.locale = Locale(identifier: "ro_RO")
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
        } catch {}
        HapticFeedback.success()
        dismiss()
    }

    private func parseBirthday(_ s: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: s)
    }

    private func sendInviteEmail(to email: String, name: String) {
        let subject = "Ești invitat în aplicația PRVIO"
        let body = "Bună \(name),\n\nEști invitat să te alături proprietății noastre în aplicația PRVIO.\n\nDescarcă aplicația și loghează-te cu acest email pentru a vedea proprietatea."
        let encoded = "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: encoded) { UIApplication.shared.open(url) }
    }
}

// MARK: - Add Social Link sheet

private struct AddSocialLinkSheet: View {
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
                                    Text(sl.platformLabel)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(platform == p ? sl.platformColor : Color.primary.opacity(0.4))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)

                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: link.platformIcon, color: link.platformColor, size: 36)
                        TextField("@username", text: $handle)
                            .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
            .navigationTitle("Adaugă rețea").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adaugă") {
                        let h = handle.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
                        guard !h.isEmpty else { return }
                        onAdd(SocialLink(platform: platform, handle: h))
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(handle.isEmpty ? Color.primary.opacity(0.3) : .blue)
                    .disabled(handle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

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
            .navigationTitle("Editează Membrul").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.blue) }
                        else { Text("Salvează").font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue) }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .confirmationDialog("Elimină \(member.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Elimină", role: .destructive) {
                    Task { await familyService.delete(member); dismiss() }
                }
                Button("Anulează", role: .cancel) {}
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
            fieldRow(icon: "person.fill", color: .blue, placeholder: "Prenume *", text: $firstName)
            div
            fieldRow(icon: "person.fill", color: Color.primary.opacity(0.4), placeholder: "Nume", text: $lastName)
            div
            fieldRow(icon: "envelope.fill", color: .orange, placeholder: "E-mail", text: $email, keyboard: .emailAddress, autocap: .never)
            div
            fieldRow(icon: "phone.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4), placeholder: "Telefon", text: $phone, keyboard: .phonePad)
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
                    Text(showBirthday ? formatted(birthday) : "Data nașterii")
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
            Text("ROL").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
            HStack(spacing: 12) {
                ColoredIconBadge(icon: kRoleIcons[role] ?? "person.fill", color: .blue, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kRoleLabels[role] ?? role.capitalized)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    if role == "tenant" {
                        Text("Acces limitat — taskuri și chat")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                Spacer()
                Picker("Rol", selection: $role) {
                    ForEach(kRoles, id: \.self) { r in
                        Label(kRoleLabels[r] ?? r.capitalized, systemImage: kRoleIcons[r] ?? "person.fill").tag(r)
                    }
                }
                .pickerStyle(.menu).tint(.blue)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private var socialLinksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REȚELE SOCIALE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
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
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(.blue)
                        Text("Adaugă rețea socială").font(.system(size: 14)).foregroundStyle(.blue)
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
            Label("Elimină membrul", systemImage: "trash")
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
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
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
        fmt.locale = Locale(identifier: "ro_RO")
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
