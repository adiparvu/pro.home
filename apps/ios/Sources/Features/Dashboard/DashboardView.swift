import SwiftUI
import MapKit

// MARK: - Dashboard (Map Home)

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var familyService: FamilyService

    @Binding var selectedTab: AppTab

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025),
            span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
        )
    )
    @State private var selectedSection: PropertySection? = nil
    @State private var pulsing = false
    @State private var showQuickActions = false

    // Property sections for map points and carousel
    private let sections = PropertySection.all

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer.ignoresSafeArea()
            topOverlay
                .padding(.top, topSafeArea + 8)
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                Spacer()
                widgetPanel
            }
        }
        .navigationBarHidden(true)
        .onAppear { startPulse() }
        .sheet(isPresented: $showQuickActions) {
            QuickActionsSheet(selectedTab: $selectedTab, isPresented: $showQuickActions)
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $mapPosition) {
            // Property Core marker
            Annotation("Property", coordinate: propertyCoordinate) {
                PropertyCoreMarker(pulsing: $pulsing) {
                    selectedSection = nil
                    HapticFeedback.impact(.medium)
                }
            }
            // Interactive property points
            ForEach(sections) { section in
                Annotation(section.name, coordinate: section.offset(from: propertyCoordinate)) {
                    PropertyPointMarker(section: section, isSelected: selectedSection?.id == section.id) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedSection = section
                        }
                        HapticFeedback.impact(.light)
                    }
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls { }
    }

    // MARK: - Top overlay

    private var topOverlay: some View {
        HStack(alignment: .center, spacing: 0) {
            // User greeting pill
            HStack(spacing: 10) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.3, green: 0.85, blue: 0.5), Color(red: 0.2, green: 0.65, blue: 0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text(avatarInitial)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Hello 👋")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)

            Spacer()

            // Notification button
            Button {
                HapticFeedback.impact(.light)
                showNotifications.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Widget panel

    private var widgetPanel: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // Property header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(propertyService.primary?.name ?? "Proprietatea mea")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    if let addr = propertyService.primary?.addressLine1 {
                        Text(addr)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    if let score = propertyService.primary?.healthScore {
                        let col: Color = score >= 80
                            ? Color(red: 0.25, green: 0.88, blue: 0.55)
                            : score >= 55 ? Color.orange : Color.red
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill").font(.system(size: 11))
                            Text("\(score)").font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(col)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(col.opacity(0.15), in: Capsule())
                    }
                    // Quick actions FAB
                    Button {
                        HapticFeedback.impact(.medium)
                        showQuickActions = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.4, green: 0.6, blue: 1.0),
                                             Color(red: 0.6, green: 0.35, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Circle()
                            )
                            .shadow(color: Color(red: 0.5, green: 0.45, blue: 0.95).opacity(0.5), radius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            // 2×2 widget grid
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                HomeWidget(
                    icon: "checklist",
                    iconColor: taskService.overdueCount > 0 ? Color.red : Color(red: 0.35, green: 0.65, blue: 1.0),
                    title: "Sarcini",
                    value: taskService.overdueCount > 0 ? "\(taskService.overdueCount)" : "\(taskService.openCount)",
                    subtitle: taskService.overdueCount > 0 ? "urgente" : "active",
                    badge: taskService.overdueCount
                ) { selectedTab = .tasks }

                HomeWidget(
                    icon: "creditcard.fill",
                    iconColor: financialService.currentMonthNet >= 0
                        ? Color(red: 0.3, green: 0.85, blue: 0.45) : Color.orange,
                    title: "Finanțe",
                    value: netFormatted,
                    subtitle: "luna aceasta"
                ) { selectedTab = .analytics }

                HomeWidget(
                    icon: "doc.fill",
                    iconColor: documentService.expiringDocs.isEmpty
                        ? Color(red: 0.55, green: 0.55, blue: 0.95) : Color.orange,
                    title: "Documente",
                    value: documentService.expiringDocs.isEmpty
                        ? "\(documentService.documents.count)"
                        : "\(documentService.expiringDocs.count)",
                    subtitle: documentService.expiringDocs.isEmpty ? "total" : "expiră curând",
                    badge: documentService.expiringDocs.count
                ) { selectedTab = .settings }

                HomeWidget(
                    icon: "person.2.fill",
                    iconColor: Color(red: 0.7, green: 0.45, blue: 0.95),
                    title: "Familie",
                    value: "\(familyService.members.count)",
                    subtitle: familyService.members.count == 1 ? "membru" : "membri"
                ) { selectedTab = .settings }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, bottomSafeArea > 0 ? bottomSafeArea + 64 : 80)
        }
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: -6)
        .ignoresSafeArea(edges: .bottom)
    }

    private var netFormatted: String {
        let sym = financialService.currencySymbol
        let abs = Int(Swift.abs(financialService.currentMonthNet))
        return financialService.currentMonthNet >= 0 ? "+\(abs)\(sym)" : "-\(abs)\(sym)"
    }

    // MARK: - Helpers

    // PropertyModel has no lat/lon fields — always use the default coordinate
    private var propertyCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 44.4268, longitude: 26.1025)
    }

    private var displayName: String {
        profileService.profile?.preferredName
            ?? auth.session?.user.email?.components(separatedBy: "@").first?.capitalized
            ?? "there"
    }

    private var avatarInitial: String {
        String(displayName.prefix(1).uppercased())
    }

    private var topSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }

    private var bottomSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 0
    }

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }
}

// MARK: - Quick Actions Sheet

struct QuickActionsSheet: View {
    @Binding var selectedTab: AppTab
    @Binding var isPresented: Bool

    @State private var showChat = false
    @State private var showAddTask = false
    @State private var showInventory = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Acțiuni rapide")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.primary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 20)

                LazyVGrid(columns: columns, spacing: 12) {
                    // Chat
                    NavigationLink {
                        ChatView()
                    } label: {
                        QuickActionTile(icon: "message.fill",
                                        color: Color(red: 0.35, green: 0.65, blue: 1.0),
                                        title: "Chat",
                                        subtitle: "Familie & colegi")
                    }
                    .buttonStyle(.plain)

                    // ARIA — dismiss + switch tab
                    Button {
                        isPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selectedTab = .assistant
                        }
                    } label: {
                        QuickActionTile(icon: "sparkles",
                                        color: Color(red: 0.6, green: 0.35, blue: 0.95),
                                        title: "ARIA",
                                        subtitle: "Asistent AI")
                    }
                    .buttonStyle(.plain)

                    // Sarcină nouă
                    NavigationLink {
                        AddTaskView()
                    } label: {
                        QuickActionTile(icon: "plus.circle.fill",
                                        color: Color(red: 0.3, green: 0.85, blue: 0.45),
                                        title: "Sarcină nouă",
                                        subtitle: "Adaugă rapid")
                    }
                    .buttonStyle(.plain)

                    // Scan scule
                    NavigationLink {
                        InventoryView()
                    } label: {
                        QuickActionTile(icon: "barcode.viewfinder",
                                        color: Color(red: 1.0, green: 0.65, blue: 0.15),
                                        title: "Scan scule",
                                        subtitle: "Inventar rapid")
                    }
                    .buttonStyle(.plain)

                    // Împrumut
                    NavigationLink {
                        InventoryView()
                    } label: {
                        QuickActionTile(icon: "arrow.left.arrow.right.circle.fill",
                                        color: Color(red: 0.95, green: 0.45, blue: 0.35),
                                        title: "Împrumut",
                                        subtitle: "Unelte & obiecte")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }
}

// MARK: - Quick Action Tile

struct QuickActionTile: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }
}

// MARK: - Home Widget Card

struct HomeWidget: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(iconColor.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    Spacer()
                    if badge > 0 {
                        Text("\(min(badge, 99))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Property Core Marker

struct PropertyCoreMarker: View {
    @Binding var pulsing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer pulse rings
                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(pulsing ? 0.08 : 0.22))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulsing ? 1.15 : 0.9)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulsing)

                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(pulsing ? 0.15 : 0.3))
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulsing ? 1.08 : 0.95)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.2), value: pulsing)

                // Core circle
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.25, green: 0.92, blue: 0.5), Color(red: 0.1, green: 0.75, blue: 0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 42, height: 42)
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.45).opacity(0.8), radius: 16)
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.45).opacity(0.4), radius: 30)

                // Icon
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Property Point Marker

struct PropertyPointMarker: View {
    let section: PropertySection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(section.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                }
                Circle()
                    .fill(isSelected
                        ? LinearGradient(colors: [section.color, section.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(isSelected ? section.color : .white.opacity(0.3), lineWidth: 1.5))
                    .shadow(color: isSelected ? section.color.opacity(0.5) : .black.opacity(0.3), radius: isSelected ? 8 : 4)
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thumbnail Card

struct ThumbnailCard: View {
    let section: PropertySection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected
                            ? LinearGradient(colors: [section.color, section.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? section.color.opacity(0.5) : .white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: isSelected ? section.color.opacity(0.4) : .black.opacity(0.2), radius: isSelected ? 12 : 4)
                    Image(systemName: section.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                }
                Text(section.name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Property Section model

struct PropertySection: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let latOffset: Double
    let lonOffset: Double

    func offset(from coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coord.latitude + latOffset * 0.0003,
            longitude: coord.longitude + lonOffset * 0.0003
        )
    }

    static let all: [PropertySection] = [
        PropertySection(name: "Casă",      icon: "house.fill",       color: Color(red: 0.35, green: 0.65, blue: 1.0),  latOffset:  1.2, lonOffset:  0.0),
        PropertySection(name: "Curte",     icon: "leaf.fill",        color: Color(red: 0.3,  green: 0.85, blue: 0.45), latOffset: -0.8, lonOffset:  0.9),
        PropertySection(name: "Garaj",     icon: "car.fill",         color: Color(red: 0.9,  green: 0.65, blue: 0.2),  latOffset: -1.2, lonOffset: -0.5),
        PropertySection(name: "Grădină",   icon: "tree.fill",        color: Color(red: 0.25, green: 0.75, blue: 0.35), latOffset:  0.5, lonOffset:  1.3),
        PropertySection(name: "Solar",     icon: "sun.max.fill",     color: Color(red: 1.0,  green: 0.85, blue: 0.2),  latOffset:  1.0, lonOffset: -1.2),
        PropertySection(name: "Foișor",    icon: "umbrella.fill",    color: Color(red: 0.7,  green: 0.45, blue: 0.95), latOffset: -0.5, lonOffset:  1.5),
        PropertySection(name: "Piscină",   icon: "drop.fill",        color: Color(red: 0.2,  green: 0.75, blue: 0.95), latOffset: -1.5, lonOffset:  0.8),
        PropertySection(name: "Utilități", icon: "bolt.fill",        color: Color(red: 1.0,  green: 0.55, blue: 0.2),  latOffset:  0.8, lonOffset: -1.5),
        PropertySection(name: "Proiecte",  icon: "hammer.fill",      color: Color(red: 0.95, green: 0.35, blue: 0.35), latOffset: -1.0, lonOffset: -1.3),
        PropertySection(name: "Documente", icon: "doc.fill",         color: Color(red: 0.55, green: 0.55, blue: 0.95), latOffset:  1.5, lonOffset:  0.6),
        PropertySection(name: "Inventar",  icon: "shippingbox.fill", color: Color(red: 0.8,  green: 0.5,  blue: 0.3),  latOffset: -0.3, lonOffset: -1.8),
    ]
}

// MARK: - Action bar items

enum ActionBarItem: CaseIterable {
    case share, favorite, info, filters, search

    var icon: String {
        switch self {
        case .share:    return "square.and.arrow.up"
        case .favorite: return "heart"
        case .info:     return "info.circle"
        case .filters:  return "slider.horizontal.3"
        case .search:   return "magnifyingglass"
        }
    }
}

// MARK: - Health Score Card

struct HealthScoreCard: View {
    let score: Int
    let isLoading: Bool

    private var color: Color {
        score >= 80 ? Color(red: 0.25, green: 0.88, blue: 0.55)
            : score >= 55 ? Color.orange
            : Color.red
    }
    private var label: String {
        score >= 80 ? "Excellent" : score >= 60 ? "Good" : score >= 40 ? "Fair" : "Needs Attention"
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: isLoading ? 0 : CGFloat(score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.1, dampingFraction: 0.8), value: score)
                    VStack(spacing: 1) {
                        Text(isLoading ? "–" : "\(score)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("/ 100")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Property Health")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(isLoading ? "Loading…" : label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color)
                    Text(isLoading ? " " : score >= 80
                         ? "Everything looks on track."
                         : "Some tasks need attention.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Stat Card

struct DashStatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Dash Task Row

struct DashTaskRow: View {
    let task: MaintenanceTask

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(task.priorityColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.38) : Color.white)
                    .strikethrough(task.isCompleted, color: Color.primary.opacity(0.35))
                    .lineLimit(1)
                Text(task.dueDateDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(task.isOverdue ? .red.opacity(0.8) : Color.primary.opacity(0.38))
            }

            Spacer()

            Text(task.statusDisplay)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Finances Snapshot

struct FinancesSnapshotCard: View {
    let income: Double
    let expenses: Double
    let net: Double
    let symbol: String
    var isLoading: Bool = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Finances")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("This month")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                if isLoading {
                    HStack { Spacer(); ProgressView().tint(.white).scaleEffect(0.8); Spacer() }
                } else {
                    HStack(spacing: 0) {
                        FinStat(label: "Income", value: formatted(income), color: Color(red: 0.25, green: 0.88, blue: 0.55))
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 34)
                        FinStat(label: "Expenses", value: formatted(expenses), color: .orange)
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 34)
                        FinStat(label: "Net", value: formatted(net), color: net >= 0 ? .white : .red)
                    }
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "\(symbol)%.0f", value)
    }
}

private struct FinStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared bg

var appBackground: Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
            : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    })
}
