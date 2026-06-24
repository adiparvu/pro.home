import SwiftUI

// MARK: - Tenant Management

struct TenantManagementView: View {
    @EnvironmentObject private var familyService:   FamilyService
    @EnvironmentObject private var propertyService: PropertyService

    @State private var showAdd        = false
    @State private var selectedTenant: FamilyMember?

    private var tenants: [FamilyMember] {
        familyService.members.filter { $0.role == "tenant" }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(titleKey: "Tenants", subtitleKey: "PROPERTY")

                if familyService.isLoading && tenants.isEmpty {
                    Spacer(); ProgressView().tint(.accentColor); Spacer()
                } else if tenants.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(tenants) { tenant in
                                tenantCard(tenant)
                                    .onTapGesture { selectedTenant = tenant }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await familyService.delete(tenant) }
                                        } label: { Label("Remove", systemImage: "trash") }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        Spacer(minLength: 100)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
        .task { await familyService.load() }
        .sheet(isPresented: $showAdd) {
            AddFamilyMemberSheet(
                propertyId: propertyService.primary?.id,
                propertyName: propertyService.primary?.name,
                preselectedRole: "tenant"
            )
            .environmentObject(familyService)
        }
        .sheet(item: $selectedTenant) { tenant in
            MemberProfileSheet(member: tenant)
                .environmentObject(familyService)
        }
    }

    // MARK: - Tenant card

    private func tenantCard(_ tenant: FamilyMember) -> some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                MemberAvatar(member: tenant, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tenant.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(tenant.swiftColor)
                        Text("Tenant")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tenant.swiftColor)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tenant.swiftColor.opacity(0.12), in: Capsule())

                    if let email = tenant.email, !email.isEmpty {
                        Label(email, systemImage: "envelope.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Quick actions
                VStack(spacing: 8) {
                    if let phone = tenant.phone, !phone.isEmpty {
                        Button {
                            if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4))
                                .frame(width: 34, height: 34)
                                .background(Color(red: 0.2, green: 0.8, blue: 0.4).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if let email = tenant.email, !email.isEmpty {
                        Button {
                            if let url = URL(string: "mailto:\(email)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                                .frame(width: 34, height: 34)
                                .background(Color.blue.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "key.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.purple.opacity(0.45))
            }
            Text("No tenants yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text("Add tenants to manage their contact info\nand lease details in one place.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showAdd = true
                HapticFeedback.impact(.medium)
            } label: {
                Label("Add Tenant", systemImage: "person.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 13)
                    .background(Color.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}
