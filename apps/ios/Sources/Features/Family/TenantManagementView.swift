import SwiftUI
import Foundation

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
                            statsStrip
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

    // MARK: - Stats strip

    private var statsStrip: some View {
        let waCount = tenants.filter { $0.socialLinks?.contains(where: { $0.platform == "whatsapp" }) == true }.count
        let phoneCount = tenants.filter { !($0.phone ?? "").isEmpty }.count
        return HStack(spacing: 12) {
            statCell(value: "\(tenants.count)", label: tenants.count == 1 ? "Tenant" : "Tenants", icon: "person.fill", color: .purple)
            if waCount > 0 {
                statCell(value: "\(waCount)", label: "WhatsApp", icon: "message.fill", color: Color(red: 0.16, green: 0.72, blue: 0.37))
            }
            if phoneCount > 0 {
                statCell(value: "\(phoneCount)", label: "With Phone", icon: "phone.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4))
            }
        }
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        GlassCard(padding: 12) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tenant card

    private func tenantCard(_ tenant: FamilyMember) -> some View {
        GlassCard(padding: 16) {
            VStack(spacing: 12) {
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

                        Label(memberSinceLabel(tenant), systemImage: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }

                    Spacer()

                    // Quick action buttons (vertical stack)
                    VStack(spacing: 6) {
                        if let phone = tenant.phone, !phone.isEmpty {
                            quickActionButton(icon: "phone.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4)) {
                                if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            quickActionButton(icon: "message.fill", color: Color(red: 0.2, green: 0.65, blue: 1.0)) {
                                if let url = URL(string: "sms:\(phone.filter { $0.isNumber })") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                        if let email = tenant.email, !email.isEmpty {
                            quickActionButton(icon: "envelope.fill", color: .blue) {
                                if let url = URL(string: "mailto:\(email)") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                }

                // WhatsApp + social links row (if available)
                if let links = tenant.socialLinks, !links.isEmpty {
                    Divider().opacity(0.4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(links) { link in
                                Button {
                                    if let url = link.openURL { UIApplication.shared.open(url) }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: link.platformIcon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(link.platformLabel)
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(link.platformColor)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(link.platformColor.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func quickActionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func memberSinceLabel(_ tenant: FamilyMember) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        let d = f.date(from: tenant.createdAt) ?? f2.date(from: tenant.createdAt) ?? Date()
        let out = DateFormatter(); out.dateStyle = .medium; out.timeStyle = .none
        return "Since \(out.string(from: d))"
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
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}
