import SwiftUI

// MARK: - Supervision settings store

struct SupervisionSettings {
    enum Section: String, CaseIterable {
        case tasks        = "tasks"
        case finances     = "finances"
        case documents    = "documents"
        case inventory    = "inventory"
        case contractors  = "contractors"
        case analytics    = "analytics"

        var label: String {
            switch self {
            case .tasks:       return String(localized: "Tasks")
            case .finances:    return String(localized: "Finances")
            case .documents:   return String(localized: "Documents")
            case .inventory:   return String(localized: "Inventory")
            case .contractors: return String(localized: "Contractors")
            case .analytics:   return String(localized: "Analytics")
            }
        }

        var icon: String {
            switch self {
            case .tasks:       return "checklist"
            case .finances:    return "banknote.fill"
            case .documents:   return "doc.fill"
            case .inventory:   return "shippingbox.fill"
            case .contractors: return "hammer.fill"
            case .analytics:   return "chart.bar.xaxis"
            }
        }

        var color: Color {
            switch self {
            case .tasks:       return .blue
            case .finances:    return Color.brandSuccess
            case .documents:   return .orange
            case .inventory:   return .indigo
            case .contractors: return .teal
            case .analytics:   return .purple
            }
        }
    }

    private static func key(_ memberId: UUID, _ section: String) -> String {
        "prvio.supervision.\(memberId.uuidString).\(section)"
    }

    static func canSee(_ memberId: UUID, section: Section) -> Bool {
        let k = key(memberId, section.rawValue)
        return UserDefaults.standard.object(forKey: k) as? Bool ?? true
    }

    static func set(_ memberId: UUID, section: Section, value: Bool) {
        UserDefaults.standard.set(value, forKey: key(memberId, section.rawValue))
    }

    static func notifyOnTaskAssign(_ memberId: UUID) -> Bool {
        let k = key(memberId, "notifyTask")
        return UserDefaults.standard.object(forKey: k) as? Bool ?? true
    }

    static func setNotifyOnTaskAssign(_ memberId: UUID, value: Bool) {
        UserDefaults.standard.set(value, forKey: key(memberId, "notifyTask"))
    }

    static func isSupervised(_ memberId: UUID) -> Bool {
        let k = "prvio.supervision.\(memberId.uuidString).enabled"
        return UserDefaults.standard.object(forKey: k) as? Bool ?? false
    }

    static func setSupervised(_ memberId: UUID, value: Bool) {
        UserDefaults.standard.set(value, forKey: "prvio.supervision.\(memberId.uuidString).enabled")
    }
}

// MARK: - Main supervision view

struct SupervisionView: View {
    @Environment(FamilyService.self) private var familyService
    @State private var selectedMember: FamilyMember? = nil
    @State private var tick = false

    var body: some View {
        VStack(spacing: 0) {

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroCard
                    memberList
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Supervision")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedMember) { member in
            MemberSupervisionDetailView(member: member, tick: $tick)
                .environment(familyService)
        }
        .task { await familyService.load() }
    }

    // MARK: Hero card

    private var heroCard: some View {
        GlassCard(padding: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color(red: 0.18, green: 0.42, blue: 1.0),
                             Color(red: 0.5, green: 0.18, blue: 0.9)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: -8) {
                    Image(systemName: "person.fill")
                        .font(AppFont.scaled(48))
                        .foregroundStyle(.white.opacity(0.5))
                    Image(systemName: "person.fill")
                        .font(AppFont.scaled(64))
                        .foregroundStyle(.white.opacity(0.75))
                    Image(systemName: "person.fill")
                        .font(AppFont.scaled(40))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .offset(x: 180, y: -10)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Family Supervision")
                        .font(AppFont.scaled(18, weight: .bold))
                        .foregroundStyle(.white)
                    Text("supervision_hint")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(3)
                }
                .padding(AppSpacing.xl)
            }
        }
    }

    // MARK: Member list

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Members")
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xxs)

            if familyService.members.isEmpty {
                GlassCard(padding: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.slash")
                            .font(AppFont.scaled(32))
                            .foregroundStyle(Color.primary.opacity(0.18))
                        Text("No members added")
                            .font(AppFont.footnote)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        Text("Add members in the Family Members section to configure supervision.")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(familyService.members.enumerated()), id: \.element.id) { idx, member in
                            supervisedMemberRow(member, isLast: idx == familyService.members.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func supervisedMemberRow(_ member: FamilyMember, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Button { selectedMember = member } label: {
                HStack(spacing: 12) {
                    MemberAvatar(member: member, size: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(AppFont.body)
                            .foregroundStyle(.primary)
                        Text(LocalizedStringKey(member.role.capitalized))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    let supervised = SupervisionSettings.isSupervised(member.id)
                    Text(LocalizedStringKey(supervised ? "Active" : "Inactive"))
                        .font(AppFont.label)
                        .foregroundStyle(supervised ? Color.brandSuccess : Color.primary.opacity(0.3))
                        .padding(.horizontal, 10).padding(.vertical, AppSpacing.xxs)
                        .background(supervised ? Color.brandSuccess.opacity(0.12) : Color.primary.opacity(AppOpacity.hairline),
                                    in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .id(tick)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 70)
            }
        }
    }
}

