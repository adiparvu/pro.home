import SwiftUI

struct FamilyView: View {
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var propertyService: PropertyService
    @State private var showAdd = false
    @State private var editingMember: FamilyMember?

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(title: "Family",
                           trailing: AnyView(
                            Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                           ))
                    .padding(.bottom, 12)

                if familyService.isLoading && familyService.members.isEmpty {
                    Spacer(); ProgressView().tint(.white); Spacer()
                } else if familyService.members.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(familyService.members) { member in
                                FamilyMemberRow(member: member)
                                    .onTapGesture { editingMember = member }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await familyService.delete(member) }
                                        } label: { Label("Remove", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            editingMember = member
                                        } label: { Label("Edit", systemImage: "pencil") }
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
        .navigationBarTitleDisplayMode(.large)
        .task { await familyService.load() }
        .sheet(isPresented: $showAdd) {
            AddFamilyMemberSheet(propertyId: propertyService.primary?.id)
        }
        .sheet(item: $editingMember) { member in
            EditFamilyMemberSheet(member: member)
        }
        .alert("Error", isPresented: Binding(
            get: { familyService.error != nil },
            set: { if !$0 { familyService.error = nil } }
        )) {
            Button("OK") { familyService.error = nil }
        } message: { Text(familyService.error ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.2.fill").font(.system(size: 52)).foregroundStyle(.white.opacity(0.15))
            Text("No family members yet").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Text("Add family members to collaborate on tasks and chat in the household.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.35)).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Add First Member") { showAdd = true }.font(.system(size: 14)).foregroundStyle(.blue)
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
                        .foregroundStyle(.white)
                    Text(member.roleLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                HStack(spacing: 10) {
                    if let phone = member.phone, !phone.isEmpty {
                        Button {
                            HapticFeedback.impact(.light)
                            if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color(red: 0.3, green: 0.85, blue: 0.5), in: Circle())
                        }
                    }
                    if let email = member.email, !email.isEmpty {
                        Button {
                            HapticFeedback.impact(.light)
                            if let url = URL(string: "mailto:\(email)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.blue, in: Circle())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Avatar component (shared)

struct MemberAvatar: View {
    let member: FamilyMember
    var size: CGFloat = 38

    var body: some View {
        if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    initials
                }
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
                        Text(m.name).font(.system(size: 15)).foregroundStyle(.white)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(m.swiftColor)
                                .font(.system(size: 20))
                        } else {
                            Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white.opacity(selected ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Add sheet

private struct AddFamilyMemberSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Environment(\.dismiss) private var dismiss
    let propertyId: UUID?

    @State private var name = ""
    @State private var role = "member"
    @State private var email = ""
    @State private var phone = ""
    @State private var color = "#5B8AF5"
    @State private var isSaving = false

    private let roles = ["owner", "partner", "child", "member", "guest"]
    private let colors = ["#5B8AF5", "#FF6B6B", "#51CF66", "#FF9F43", "#A29BFE", "#FD79A8", "#00CEC9", "#FDCB6E"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        avatarPreview
                        colorPicker
                        fields
                        rolePicker
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Member").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.blue) }
                        else { Text("Add").font(.system(size: 15, weight: .semibold)).foregroundStyle(name.isEmpty ? .white.opacity(0.3) : .blue) }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private var avatarPreview: some View {
        ZStack {
            Circle().fill((Color(hex: color) ?? .blue).opacity(0.22))
                .overlay(Circle().strokeBorder((Color(hex: color) ?? .blue).opacity(0.5), lineWidth: 2))
            Text(name.isEmpty ? "?" : String(name.prefix(2)).uppercased())
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: color) ?? .blue)
        }
        .frame(width: 80, height: 80)
        .padding(.top, 8)
    }

    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(colors, id: \.self) { c in
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

    private var fields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                TextField("Full name *", text: $name).font(.system(size: 15)).foregroundStyle(.white).tint(.blue)
            }.padding(.horizontal, 16).padding(.vertical, 13)
            Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
            HStack(spacing: 12) {
                Image(systemName: "phone.fill").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                TextField("Phone (optional)", text: $phone).font(.system(size: 15)).foregroundStyle(.white).tint(.blue).keyboardType(.phonePad)
            }.padding(.horizontal, 16).padding(.vertical, 13)
            Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                TextField("Email (optional)", text: $email).font(.system(size: 15)).foregroundStyle(.white).tint(.blue).keyboardType(.emailAddress).autocapitalization(.none)
            }.padding(.horizontal, 16).padding(.vertical, 13)
        }
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROLE").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(roles, id: \.self) { r in
                        Button { role = r } label: {
                            Text(r.capitalized)
                                .font(.system(size: 13, weight: role == r ? .semibold : .regular))
                                .foregroundStyle(role == r ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(role == r ? .white : .white.opacity(0.08), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        try? await familyService.add(
            name: name, role: role,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone,
            color: color, propertyId: propertyId
        )
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - Edit sheet

private struct EditFamilyMemberSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Environment(\.dismiss) private var dismiss
    var member: FamilyMember

    @State private var name: String
    @State private var role: String
    @State private var email: String
    @State private var phone: String
    @State private var color: String
    @State private var isSaving = false
    @State private var showDeleteConfirm = false

    private let roles = ["owner", "partner", "child", "member", "guest"]
    private let colors = ["#5B8AF5", "#FF6B6B", "#51CF66", "#FF9F43", "#A29BFE", "#FD79A8", "#00CEC9", "#FDCB6E"]

    init(member: FamilyMember) {
        self.member = member
        _name  = State(initialValue: member.name)
        _role  = State(initialValue: member.role)
        _email = State(initialValue: member.email ?? "")
        _phone = State(initialValue: member.phone ?? "")
        _color = State(initialValue: member.color)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle().fill((Color(hex: color) ?? .blue).opacity(0.22))
                                .overlay(Circle().strokeBorder((Color(hex: color) ?? .blue).opacity(0.5), lineWidth: 2))
                            Text(name.isEmpty ? "?" : String(name.prefix(2)).uppercased())
                                .font(.system(size: 28, weight: .bold)).foregroundStyle(Color(hex: color) ?? .blue)
                        }.frame(width: 80, height: 80).padding(.top, 8)

                        HStack(spacing: 10) {
                            ForEach(colors, id: \.self) { c in
                                Button { color = c } label: {
                                    Circle().fill(Color(hex: c) ?? .blue).frame(width: 30, height: 30)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: color == c ? 2 : 0))
                                        .scaleEffect(color == c ? 1.15 : 1.0).animation(.spring(response: 0.2), value: color)
                                }.buttonStyle(.plain)
                            }
                        }

                        VStack(spacing: 0) {
                            row("person.fill", "Name", $name)
                            div
                            row("phone.fill", "Phone", $phone, keyboard: .phonePad)
                            div
                            row("envelope.fill", "Email", $email, keyboard: .emailAddress)
                        }
                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(roles, id: \.self) { r in
                                    Button { role = r } label: {
                                        Text(r.capitalized)
                                            .font(.system(size: 13, weight: role == r ? .semibold : .regular))
                                            .foregroundStyle(role == r ? .black : .white.opacity(0.7))
                                            .padding(.horizontal, 14).padding(.vertical, 8)
                                            .background(role == r ? .white : .white.opacity(0.08), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        Button { showDeleteConfirm = true } label: {
                            Label("Remove Member", systemImage: "trash")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(.red)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Edit Member").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.blue) }
                        else { Text("Save").font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue) }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .confirmationDialog("Remove \(member.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task {
                        await familyService.delete(member)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func row(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
            TextField(ph, text: b).font(.system(size: 15)).foregroundStyle(.white).tint(.blue).keyboardType(keyboard)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var div: some View { Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = member
        updated.name = name; updated.role = role
        updated.email = email.isEmpty ? nil : email
        updated.phone = phone.isEmpty ? nil : phone
        updated.color = color
        await familyService.update(updated)
        HapticFeedback.success()
        dismiss()
    }
}
