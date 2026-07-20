import SwiftUI

// MARK: - Constants

let kRoles = ["owner", "partner", "member", "teen", "child", "tenant", "worker", "guest"]
let kRoleLabels: [String: String] = [
    "owner": "Owner", "partner": "Partner", "child": "Child", "teen": "Teen",
    "member": "Member", "tenant": "Tenant", "worker": "Worker", "guest": "Guest"
]
let kRoleIcons: [String: String] = [
    "owner": "house.fill", "partner": "heart.fill", "child": "figure.child",
    "teen": "figure.wave", "member": "person.fill", "tenant": "key.fill",
    "worker": "hammer.fill", "guest": "person.badge.clock"
]
let kRoleDescriptions: [String: String] = [
    "owner":   "Full access to everything",
    "partner": "Full access, same as the owner",
    "member":  "Family adult — home, tasks, finances",
    "teen":    "mem_role_teen_desc",
    "child":   "Limited access, with supervision",
    "tenant":  "Sees own tasks and shared bills",
    "worker":  "Sees only assigned tasks and chat",
    "guest":   "Chat only — nothing from the home",
]
let kColors = ["#5B8AF5", "#FF6B6B", "#51CF66", "#FF9F43", "#A29BFE", "#FD79A8", "#00CEC9", "#FDCB6E"]
let kSocialPlatforms = ["instagram", "facebook", "whatsapp", "linkedin", "tiktok", "twitter", "pinterest"]

// MARK: - E-mail sanity — the one client-side authority
//
// Shared by the add-member, tenant and edit-member flows so an invitation can
// never be handed to something like "bb". Deliberately light-weight: the
// server still validates properly; this only catches obvious non-addresses
// before anything is created.
enum EmailFormat {
    static func isValid(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespaces)
            .range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#, options: .regularExpression) != nil
    }
}

// MARK: - Add Social Link sheet

struct AddSocialLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (SocialLink) -> Void

    @State private var platform = "instagram"
    @State private var handle = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        ForEach(kSocialPlatforms, id: \.self) { p in
                            let sl = SocialLink(platform: p, handle: "")
                            let isSelected = platform == p
                            Button {
                                HapticFeedback.selection()
                                platform = p
                            } label: {
                                VStack(spacing: 6) {
                                    // Unselected tiles keep full brand color
                                    // (that's what makes them recognizable)
                                    // but recede via opacity and scale; the
                                    // selection ring floats just outside the
                                    // chosen badge, so the cue is shape and
                                    // motion, never color alone.
                                    SocialBrandIcon(platform: p, size: 48)
                                        .opacity(isSelected ? 1 : 0.45)
                                        .scaleEffect(isSelected ? 1 : 0.92)
                                        .overlay {
                                            if isSelected {
                                                RoundedRectangle(cornerRadius: 48 * 0.235 + 3, style: .continuous)
                                                    .strokeBorder(sl.platformColor, lineWidth: 2)
                                                    .padding(-3.5)
                                            }
                                        }
                                    Text(LocalizedStringKey(sl.platformLabel))
                                        .font(AppFont.scaled(9, weight: .medium))
                                        .foregroundStyle(isSelected ? sl.platformColor : Color.primary.opacity(0.4))
                                }
                                .animation(.smooth(duration: 0.22), value: platform)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)

                    HStack(spacing: 12) {
                        SocialBrandIcon(platform: platform, size: 36)
                        TextField("@username", text: $handle)
                            .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
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
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Roles & permissions reference
//
// The detailed "who sees what" sheet behind the ⓘ next to ROLE. The lists
// mirror the real gating matrices (SettingsView.allowed / allowedApp and the
// members-management rule) — if the matrix changes, update this too.

struct RolePermissionsSheet: View {
    var highlighted: String? = nil
    @Environment(\.dismiss) private var dismiss

    private struct RoleSpec: Identifiable {
        let id: String
        let sees: [LocalizedStringKey]
        let hidden: [LocalizedStringKey]
    }

    private static let allFeatures: [LocalizedStringKey] = [
        "My Property", "Documents", "Plans & 3D", "Finances", "Inventory",
        "Supplies", "Plants", "Deliveries", "Utilities", "Contractors",
        "Analytics", "Property Report", "Tenants", "Appliances",
        "Photo Journal", "Seasonal Checklists", "Paint Colors",
        "Property Value", "Guest Mode", "Members", "Chat",
        "Live Activities", "Floating Buttons", "NFC Keys", "Integrations"
    ]

    private static let specs: [RoleSpec] = [
        RoleSpec(id: "owner", sees: allFeatures, hidden: []),
        RoleSpec(id: "partner", sees: allFeatures, hidden: []),
        RoleSpec(id: "member",
                 sees: ["My Property", "Documents", "Plans & 3D", "Finances",
                        "Inventory", "Supplies", "Plants", "Deliveries",
                        "Utilities", "Contractors", "Analytics",
                        "Property Report", "Appliances", "Photo Journal",
                        "Seasonal Checklists", "Paint Colors",
                        "Members", "Chat", "Live Activities",
                        "Floating Buttons", "NFC Keys", "Integrations"],
                 hidden: ["Tenants", "Guest Mode", "Property Value"]),
        RoleSpec(id: "tenant",
                 sees: ["Documents", "Supplies", "Plants", "Deliveries",
                        "Utilities", "Contractors", "Appliances",
                        "Photo Journal", "Seasonal Checklists", "Paint Colors",
                        "Chat", "Live Activities", "Floating Buttons", "NFC Keys"],
                 hidden: ["My Property", "Plans & 3D", "Finances", "Inventory",
                          "Analytics", "Property Report", "Tenants",
                          "Property Value", "Guest Mode",
                          "Members", "Integrations"]),
        // Teens share the child feature set today (SettingsView.allowed treats
        // .familyChild and .familyTeen identically) — they just aren't listed
        // under Supervision. If the gating matrix ever splits them, split here.
        RoleSpec(id: "teen",
                 sees: ["Supplies", "Plants", "Deliveries", "Photo Journal",
                        "Seasonal Checklists", "Chat"],
                 hidden: ["My Property", "Documents", "Plans & 3D", "Finances",
                          "Inventory", "Utilities", "Contractors", "Analytics",
                          "Property Report", "Tenants", "Appliances",
                          "Paint Colors", "Property Value", "Guest Mode",
                          "Members", "Live Activities",
                          "Floating Buttons", "NFC Keys", "Integrations"]),
        RoleSpec(id: "child",
                 sees: ["Supplies", "Plants", "Deliveries", "Photo Journal",
                        "Seasonal Checklists", "Chat"],
                 hidden: ["My Property", "Documents", "Plans & 3D", "Finances",
                          "Inventory", "Utilities", "Contractors", "Analytics",
                          "Property Report", "Tenants", "Appliances",
                          "Paint Colors", "Property Value", "Guest Mode",
                          "Members", "Live Activities",
                          "Floating Buttons", "NFC Keys", "Integrations"]),
        RoleSpec(id: "worker",
                 sees: ["Documents", "Contractors", "Deliveries", "Appliances",
                        "Seasonal Checklists", "Photo Journal", "Chat",
                        "Live Activities", "Floating Buttons"],
                 hidden: ["My Property", "Plans & 3D", "Finances", "Inventory",
                          "Supplies", "Plants", "Utilities", "Analytics",
                          "Property Report", "Tenants", "Paint Colors",
                          "Property Value", "Guest Mode",
                          "Members", "NFC Keys", "Integrations"]),
        RoleSpec(id: "guest",
                 sees: ["Chat"],
                 hidden: ["My Property", "Documents", "Plans & 3D", "Finances",
                          "Inventory", "Supplies", "Plants", "Deliveries",
                          "Utilities", "Contractors", "Analytics",
                          "Property Report", "Tenants", "Appliances",
                          "Photo Journal", "Seasonal Checklists", "Paint Colors",
                          "Property Value", "Guest Mode",
                          "Members", "Live Activities", "Floating Buttons",
                          "NFC Keys", "Integrations"]),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Text("Every role sees only its own slice of the home. Owners and partners can change a member's role at any time.")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.secondaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(Self.specs) { spec in
                            roleCard(spec)
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Roles & permissions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.primary)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    @ViewBuilder
    private func roleCard(_ spec: RoleSpec) -> some View {
        let isCurrent = spec.id == highlighted
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: kRoleIcons[spec.id] ?? "person.fill",
                                 color: isCurrent ? Color.accentColor : .gray, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(kRoleLabels[spec.id] ?? spec.id.capitalized))
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        if isCurrent {
                            Text("Selected")
                                .font(AppFont.scaled(10, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                    if let desc = kRoleDescriptions[spec.id] {
                        Text(LocalizedStringKey(desc))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
                Spacer()
            }

            permissionList("Can see and use", items: spec.sees,
                           icon: "checkmark.circle.fill", tint: Color.brandSuccess)
            if !spec.hidden.isEmpty {
                permissionList("Not visible", items: spec.hidden,
                               icon: "eye.slash.fill", tint: Color.secondaryTextColor)
            }
        }
        .padding(AppSpacing.base)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor.opacity(0.5)
                                        : Color.primary.opacity(AppOpacity.subtleFill),
                              lineWidth: isCurrent ? 1.2 : 0.5)
        )
    }

    private func permissionList(_ title: LocalizedStringKey,
                                items: [LocalizedStringKey],
                                icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(tint)
            FlowLayoutChips(items: items, icon: icon, tint: tint)
        }
    }
}

/// Compact wrapping chip rows for permission items.
private struct FlowLayoutChips: View {
    let items: [LocalizedStringKey]
    let icon: String
    let tint: Color

    var body: some View {
        // Simple 2-column grid keeps rows compact without a custom Layout.
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(AppFont.scaled(10))
                        .foregroundStyle(tint)
                    Text(item)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }
}
