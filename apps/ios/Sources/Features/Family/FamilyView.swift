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
                                        } label: { Label("Remove", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button { selectedMember = member } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.accentColor)
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 110)
                    }
                }
            }
        }
        .navigationTitle("Family")
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
            AddFamilyMemberSheet(
                propertyId: propertyService.primary?.id,
                propertyName: propertyService.primary?.name
            )
        }
        .sheet(item: $selectedMember) { member in
            MemberProfileSheet(member: member)
        }
        .alert("Error", isPresented: Binding(
            get: { familyService.error != nil },
            set: { if !$0 { familyService.error = nil } }
        )) {
            Button("OK") { familyService.error = nil }
        } message: { Text(LocalizedStringKey(familyService.error ?? "")) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "person.2.fill").font(.system(size: 52)).foregroundStyle(Color.primary.opacity(0.15))
            Text("No members").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
            Text("Add family members to collaborate on tasks and chat.").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.35)).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Add first member") { showAdd = true }.font(.system(size: 14)).foregroundStyle(Color.accentColor)
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
                        Text(LocalizedStringKey(member.roleLabel))
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
        }
        .glassCircle()
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
