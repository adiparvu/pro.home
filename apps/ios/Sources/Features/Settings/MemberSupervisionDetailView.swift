import SwiftUI

// MARK: - Member supervision detail

struct MemberSupervisionDetailView: View {
    let member: FamilyMember
    @Binding var tick: Bool

    @State private var supervised: Bool
    @State private var sectionToggles: [SupervisionSettings.Section: Bool] = [:]
    @State private var notifyOnTask: Bool

    init(member: FamilyMember, tick: Binding<Bool>) {
        self.member = member
        _tick = tick
        _supervised = State(initialValue: SupervisionSettings.isSupervised(member.id))
        _notifyOnTask = State(initialValue: SupervisionSettings.notifyOnTaskAssign(member.id))
        var toggles: [SupervisionSettings.Section: Bool] = [:]
        for s in SupervisionSettings.Section.allCases {
            toggles[s] = SupervisionSettings.canSee(member.id, section: s)
        }
        _sectionToggles = State(initialValue: toggles)
    }

    var body: some View {
        VStack(spacing: 0) {

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    enableToggleCard
                    if supervised { sectionsCard }
                    if supervised { notificationsCard }
                    if supervised { infoCard }
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
                .animation(.spring(response: 0.4), value: supervised)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Enable card

    private var enableToggleCard: some View {
        GlassCard(padding: 0) {
            HStack(spacing: 12) {
                MemberAvatar(member: member, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable supervision")
                        .font(AppFont.body)
                    Text(LocalizedStringKey(supervised ? "Restrictions are active" : "Member has full access"))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $supervised)
                    .labelsHidden()
                    .tint(.accentColor)
                    .onChange(of: supervised) { _, val in
                        SupervisionSettings.setSupervised(member.id, value: val)
                        HapticFeedback.selection()
                        tick.toggle()
                    }
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.base)
        }
    }

    // MARK: Sections card

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT THEY CAN SEE")
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(SupervisionSettings.Section.allCases.enumerated()), id: \.element) { idx, section in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .fill(section.color.opacity(0.14))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: section.icon)
                                        .font(AppFont.footnoteEmphasis)
                                        .foregroundStyle(section.color)
                                }
                                Text(LocalizedStringKey(section.label))
                                    .font(AppFont.scaled(15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { sectionToggles[section] ?? true },
                                    set: { val in
                                        sectionToggles[section] = val
                                        SupervisionSettings.set(member.id, section: section, value: val)
                                        HapticFeedback.selection()
                                    }
                                ))
                                .labelsHidden()
                                .tint(.accentColor)
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)

                            if idx < SupervisionSettings.Section.allCases.count - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 58)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Notifications card

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTIFICATIONS")
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                            .fill(Color.blue.opacity(0.14))
                            .frame(width: 32, height: 32)
                        Image(systemName: "bell.badge.fill")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Task notifications")
                            .font(AppFont.scaled(15))
                        Text("Receive a notification when a task is assigned to you")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $notifyOnTask)
                        .labelsHidden()
                        .tint(.accentColor)
                        .onChange(of: notifyOnTask) { _, val in
                            SupervisionSettings.setNotifyOnTaskAssign(member.id, value: val)
                            HapticFeedback.selection()
                        }
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            }
        }
    }

    // MARK: Info card

    private var infoCard: some View {
        GlassCard(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(AppFont.scaled(18))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("How it works")
                        .font(AppFont.captionEmphasis)
                    Text("Restrictions apply at the device level. \(member.name) will only see the enabled sections. Assigned tasks will automatically send them a notification.")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                }
            }
        }
    }
}
