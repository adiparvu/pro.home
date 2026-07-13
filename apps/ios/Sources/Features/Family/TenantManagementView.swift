import SwiftUI
import Foundation

// MARK: - Tenant Management

struct TenantManagementView: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings

    @State private var showAdd        = false
    @State private var selectedTenant: FamilyMember?
    @State private var searchText = ""

    private var tenants: [FamilyMember] {
        let base = familyService.members.filter { $0.role == "tenant" }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.name.matchesSearch(searchText)
                || ($0.email ?? "").matchesSearch(searchText)
                || ($0.phone ?? "").matchesSearch(searchText)
        }
    }

    /// Cashflow snapshot over every lease on the property — income (converted
    /// to the preferred currency), next rent due, deposits, occupancy.
    private var rentRoll: RentRoll {
        RentRoll.build(
            leases: Array(familyService.leases.values),
            nameFor: { id in familyService.members.first { $0.id == id }?.name
                ?? String(localized: "agenda_lease_tenant") },
            convert: { amount, code in
                currencyService.convert(amount, from: code, to: appSettings.preferredCurrency) },
            preferred: appSettings.preferredCurrency)
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if familyService.isLoading && tenants.isEmpty {
                    Spacer(); ProgressView().tint(.accentColor); Spacer()
                } else if tenants.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            if case let roll = rentRoll, !roll.isEmpty { RentRollCard(roll: roll) }
                            statsStrip
                            leaseAlerts
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
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.md)
                        Spacer(minLength: 100)
                    }
                }
            }
        }
        .navigationTitle("Tenants")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(AppFont.scaled(19, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add tenant")
            }
        }
        .task {
            await familyService.load()
            if let pid = propertyService.primary?.id {
                await familyService.loadLeases(propertyId: pid)
            }
        }
        .sheet(isPresented: $showAdd) {
            TenantFormSheet(
                propertyId: propertyService.primary?.id,
                propertyName: propertyService.primary?.name
            )
            .environment(familyService)
        }
        .sheet(item: $selectedTenant) { tenant in
            MemberProfileSheet(member: tenant)
                .environment(familyService)
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
                statCell(value: "\(phoneCount)", label: "With Phone", icon: "phone.fill", color: Color.brandSuccess)
            }
        }
    }

    private func statCell(value: String, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        GlassCard(padding: 12) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(color)
                Text(value)
                    .font(AppFont.scaled(20, weight: .bold))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(AppFont.scaled(10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Lease alerts (renewal window: 60 days)

    @ViewBuilder
    private var leaseAlerts: some View {
        let flagged = tenants.compactMap { tenant -> (FamilyMember, TenantLease)? in
            guard let lease = familyService.leases[tenant.id],
                  lease.isEndingSoon || lease.hasEnded else { return nil }
            return (tenant, lease)
        }
        if !flagged.isEmpty {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(flagged, id: \.0.id) { tenant, lease in
                        Button {
                            selectedTenant = tenant
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: lease.hasEnded
                                      ? "exclamationmark.octagon.fill"
                                      : "exclamationmark.triangle.fill")
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(lease.hasEnded ? Color.brandDanger : .orange)
                                Text(String(format: String(localized: lease.hasEnded
                                                           ? "tenant_lease_ended %@"
                                                           : "tenant_lease_ending %@"),
                                            tenant.name))
                                    .font(AppFont.scaled(13))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.primary.opacity(0.25))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Image(systemName: "key.fill")
                                .font(AppFont.scaled(10))
                                .foregroundStyle(tenant.swiftColor)
                            Text("Tenant")
                                .font(AppFont.caption)
                                .foregroundStyle(tenant.swiftColor)
                        }
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background(tenant.swiftColor.opacity(0.12), in: Capsule())

                        if let email = tenant.email, !email.isEmpty {
                            Label(email, systemImage: "envelope.fill")
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                .lineLimit(1)
                        }

                        Label(memberSinceLabel(tenant), systemImage: "calendar")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))

                        if let lease = familyService.leases[tenant.id] {
                            HStack(spacing: 6) {
                                if let rent = lease.rentDisplay {
                                    Label("\(rent)/\(String(localized: "month"))", systemImage: "banknote.fill")
                                        .font(AppFont.label)
                                        .foregroundStyle(Color.brandSuccess)
                                }
                                if let end = lease.endDisplay {
                                    // The urgency is visible at a glance:
                                    // orange inside the renewal window, red
                                    // once the lease is over.
                                    Label(String(format: String(localized: "until %@"), end), systemImage: "calendar.badge.exclamationmark")
                                        .font(AppFont.scaled(11, weight: lease.isEndingSoon || lease.hasEnded ? .semibold : .regular))
                                        .foregroundStyle(lease.hasEnded ? Color.brandDanger
                                                         : lease.isEndingSoon ? .orange
                                                         : Color.primary.opacity(AppOpacity.mediumText))
                                }
                                if lease.isEndingSoon, let days = lease.daysUntilEnd {
                                    Text(String(format: String(localized: "tenant_lease_days_left %lld"), days))
                                        .font(AppFont.scaled(10, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, AppSpacing.xs).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }

                    Spacer()

                    // Quick action buttons (vertical stack)
                    VStack(spacing: 6) {
                        if let phone = tenant.phone, !phone.isEmpty {
                            quickActionButton(icon: "phone.fill", color: Color.brandSuccess) {
                                if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            quickActionButton(icon: "message.fill", color: Color.brandSkyBlue) {
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

                // WhatsApp + social links row (if available). Entries without
                // a truthful URL (a WhatsApp value that isn't a phone number)
                // stay visible but inert — never a dead button.
                let links = SocialLinksRow.displayable(tenant.socialLinks)
                if !links.isEmpty {
                    Divider().opacity(0.4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(links) { link in
                                if let url = link.openURL {
                                    Button {
                                        UIApplication.shared.open(url)
                                    } label: {
                                        socialChip(link)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        String(format: String(localized: "soc_open_profile_fmt"),
                                               link.platformLabel))
                                } else {
                                    socialChip(link)
                                        .accessibilityLabel(
                                            String(format: String(localized: "soc_no_link_fmt"),
                                                   link.platformLabel, link.sanitizedHandle))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func socialChip(_ link: SocialLink) -> some View {
        HStack(spacing: 5) {
            SocialBrandIcon(platform: link.platform, size: 18)
            Text(link.platformLabel)
                .font(AppFont.caption)
        }
        .foregroundStyle(link.platformColor)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(link.platformColor.opacity(0.1), in: Capsule())
    }

    private func quickActionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppFont.scaled(13))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            icon == "phone.fill" ? "Call tenant"
            : icon == "message.fill" ? "Send SMS"
            : "Email tenant"
        )
    }

    // Static formatters — three were being built per card per render.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func memberSinceLabel(_ tenant: FamilyMember) -> String {
        let d = Self.isoFractional.date(from: tenant.createdAt)
            ?? Self.isoPlain.date(from: tenant.createdAt) ?? Date()
        return String(format: String(localized: "tenant_since %@"), AppDate.medium.string(from: d))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "key.fill")
                .font(AppFont.scaled(30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 80, height: 80)
                .glassCircle()
            Text("No tenants yet")
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text("Add tenants to manage their contact info\nand lease details in one place.")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showAdd = true
                HapticFeedback.impact(.medium)
            } label: {
                Label("Add Tenant", systemImage: "person.badge.plus")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppSpacing.xxl).padding(.vertical, 13)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
}
