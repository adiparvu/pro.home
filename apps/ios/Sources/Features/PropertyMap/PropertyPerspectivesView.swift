import SwiftUI

// MARK: - Perspective Model

private struct Perspective: Identifiable {
    let id = UUID()
    let role: String
    let title: String
    let icon: String
    let color: Color
    let description: String
    let highlights: [PerspectiveHighlight]
}

private struct PerspectiveHighlight: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let color: Color
    var tab: AppTab? = nil
    var action: (() -> Void)? = nil
}

// MARK: - PropertyPerspectivesView

struct PropertyPerspectivesView: View {
    @EnvironmentObject private var propertyService:  PropertyService
    @EnvironmentObject private var taskService:      TaskService
    @EnvironmentObject private var documentService:  DocumentService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var familyService:    FamilyService
    @EnvironmentObject private var applianceService: ApplianceService
    @EnvironmentObject private var router:           AppRouter

    @State private var selectedRole = "owner"

    private var perspectives: [Perspective] {
        let tasks     = taskService.tasks
        let overdue   = tasks.filter { $0.isCompleted == false && isDue($0.dueDate) }
        let tenants   = familyService.members.filter { $0.role == "tenant" }
        let income    = financialService.records.filter { $0.type == "income" }.reduce(0.0) { $0 + $1.amount }
        let expenses  = financialService.records.filter { $0.type != "income" }.reduce(0.0) { $0 + $1.amount }

        return [
            Perspective(
                role: "owner",
                title: "Owner",
                icon: "house.fill",
                color: .blue,
                description: "Full access — property health, finances, tasks, and all zones.",
                highlights: [
                    .init(icon: "heart.fill",           label: "Health Score",  value: propertyService.primary?.healthScore.map { "\($0)%" } ?? "—", color: .green,   tab: .digitalTwin),
                    .init(icon: "banknote.fill",         label: "Net Balance",   value: "\(financialService.currencySymbol)\(Int(income - expenses))", color: income >= expenses ? .green : .red, tab: .settings),
                    .init(icon: "checkmark.circle.fill", label: "Open Tasks",    value: "\(tasks.filter { !$0.isCompleted }.count)", color: .orange, tab: .tasks),
                    .init(icon: "doc.text.fill",         label: "Documents",     value: "\(documentService.documents.count)", color: .purple,  tab: .settings),
                    .init(icon: "washer.fill",           label: "Appliances",    value: "\(applianceService.appliances.count)", color: Color(red: 0.2, green: 0.55, blue: 0.95), tab: .settings),
                    .init(icon: "person.2.fill",         label: "Family",        value: "\(familyService.members.count)", color: .teal, tab: .settings),
                ]
            ),
            Perspective(
                role: "tenant",
                title: "Tenant",
                icon: "key.fill",
                color: .purple,
                description: "Tenant-facing view — shared areas, visible tasks, and contact.",
                highlights: [
                    .init(icon: "key.fill",              label: "Tenants",       value: "\(tenants.count)",         color: .purple,  tab: .settings),
                    .init(icon: "checkmark.circle.fill", label: "Shared Tasks",  value: "\(tasks.filter { !$0.isCompleted }.count)", color: .orange, tab: .tasks),
                    .init(icon: "exclamationmark.circle.fill", label: "Overdue", value: "\(overdue.count)",         color: overdue.isEmpty ? .green : .red, tab: .tasks),
                    .init(icon: "person.fill",           label: "Owner Contact", value: propertyService.primary?.name ?? "—", color: .blue),
                ]
            ),
            Perspective(
                role: "guest",
                title: "Guest",
                icon: "person.badge.clock",
                color: Color(red: 0.95, green: 0.55, blue: 0.15),
                description: "Temporary access — visible areas and emergency contacts only.",
                highlights: [
                    .init(icon: "wifi",           label: "Wi-Fi Access",   value: "Enabled",  color: .green),
                    .init(icon: "phone.fill",     label: "Emergency",      value: "Saved",    color: .red),
                    .init(icon: "map.fill",       label: "Property",       value: propertyService.primary?.addressLine1 ?? "—", color: .blue, tab: .digitalTwin),
                    .init(icon: "person.fill",    label: "Host",           value: "Available", color: .teal),
                ]
            ),
            Perspective(
                role: "contractor",
                title: "Contractor",
                icon: "wrench.and.screwdriver.fill",
                color: Color(red: 0.2, green: 0.72, blue: 0.45),
                description: "Service access — maintenance tasks, systems, and appliances.",
                highlights: [
                    .init(icon: "checkmark.circle.fill", label: "Maintenance Tasks", value: "\(tasks.filter { $0.category == "maintenance" && !$0.isCompleted }.count)", color: .orange, tab: .tasks),
                    .init(icon: "washer.fill",       label: "Appliances",  value: "\(applianceService.appliances.count)", color: Color(red: 0.2, green: 0.55, blue: 0.95), tab: .settings),
                    .init(icon: "exclamationmark.circle.fill", label: "Overdue", value: "\(overdue.count)", color: overdue.isEmpty ? .green : .red, tab: .tasks),
                    .init(icon: "shield.lefthalf.filled", label: "Under Warranty", value: "\(applianceService.appliances.filter { $0.warrantyUntil != nil }.count)", color: .teal, tab: .settings),
                ]
            ),
        ]
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(titleKey: "Perspectives", subtitleKey: "PROPERTY")

                // Role selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Spacer(minLength: 20)
                        ForEach(perspectives) { p in
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedRole = p.role }
                                HapticFeedback.selection()
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: p.icon)
                                        .font(AppFont.captionStrong)
                                    Text(p.title)
                                        .font(AppFont.captionEmphasis)
                                }
                                .foregroundStyle(selectedRole == p.role ? .white : p.color)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(
                                    selectedRole == p.role ? AnyShapeStyle(p.color) : AnyShapeStyle(p.color.opacity(0.12)),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 20)
                    }
                }
                .padding(.vertical, 12)

                ScrollView(showsIndicators: false) {
                    if let p = perspectives.first(where: { $0.role == selectedRole }) {
                        perspectiveContent(p)
                    }
                    Spacer(minLength: 100)
                }
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Perspective content

    private func perspectiveContent(_ p: Perspective) -> some View {
        VStack(spacing: 16) {
            // Hero card
            GlassCard(padding: 20) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(p.color.opacity(0.15)).frame(width: 56, height: 56)
                        Image(systemName: p.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(p.color)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title + " View")
                            .font(.system(size: 17, weight: .bold))
                        Text(p.description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 20)

            // Stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(p.highlights) { h in
                    Button {
                        if let tab = h.tab {
                            router.selectedTab = tab
                        }
                        h.action?()
                    } label: {
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: h.icon)
                                        .font(AppFont.footnoteEmphasis)
                                        .foregroundStyle(h.color)
                                    Text(h.label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                    if h.tab != nil {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(Color.primary.opacity(0.25))
                                    }
                                }
                                Text(h.value)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(h.color)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            // Perspective-specific tips
            tipCard(for: p)
                .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func tipCard(for p: Perspective) -> some View {
        let tips: [String]
        switch p.role {
        case "owner":
            tips = [
                "Run a Property Report for a full printable overview.",
                "Use the Automation Builder to automate warranty alerts.",
                "Check the Twin health score monthly.",
            ]
        case "tenant":
            tips = [
                "Contact your owner from Chat.",
                "Shared tasks appear in your Tasks tab.",
                "Document your lease under Documents.",
            ]
        case "guest":
            tips = [
                "Emergency contacts are saved in Settings → Emergency Contacts.",
                "Your host can share Wi-Fi via the Guest Mode QR.",
            ]
        default:
            tips = [
                "View maintenance tasks assigned to you in the Tasks tab.",
                "Appliance manuals are stored in Documents.",
                "Contact the owner via Chat.",
            ]
        }

        return GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow)
                    Text("Tips for this view")
                        .font(AppFont.captionEmphasis)
                }
                ForEach(tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(p.color)
                            .padding(.top, 1)
                        Text(tip)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func isDue(_ dateStr: String?) -> Bool {
        guard let s = dateStr else { return false }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        let date = f1.date(from: s) ?? f2.date(from: s)
        return (date ?? .distantFuture) < Date()
    }
}
