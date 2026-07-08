import SwiftUI
import RoomPlan
import PhotosUI
import UniformTypeIdentifiers

struct BlueprintsView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @State private var service = BlueprintService()
    @State private var showRoomScan = false
    @State private var showAddPlan = false
    @State private var previewItem: HomeScan?
    @State private var renameItem: HomeScan?
    @State private var renameText = ""
    @State private var showSaveAsZone = false
    @State private var pendingZoneName = ""
    // Bumped when a per-plan lock toggles so the (UserDefaults-backed) badges refresh.
    @State private var lockRefresh = 0
    @State private var searchText = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    /// Runs `action` immediately for unlocked plans; locked ones require
    /// Face ID / passcode first.
    private func withLockCheck(_ scan: HomeScan, _ action: @escaping () -> Void) {
        guard ItemLockStore.isLocked(scan.id.uuidString, in: .plans) else { action(); return }
        Task {
            if await PrivacyAuth.authenticate(reason: String(localized: "Unlock \"\(scan.name)\"")) {
                await MainActor.run { action() }
            }
        }
    }

    /// Locking is free; removing a lock itself requires authentication.
    private func toggleLock(_ scan: HomeScan) {
        let id = scan.id.uuidString
        if ItemLockStore.isLocked(id, in: .plans) {
            Task {
                if await PrivacyAuth.authenticate(reason: String(localized: "Remove lock from \"\(scan.name)\"")) {
                    await MainActor.run {
                        ItemLockStore.setLocked(id, in: .plans, false)
                        HapticFeedback.success()
                        lockRefresh += 1
                    }
                }
            }
        } else {
            ItemLockStore.setLocked(id, in: .plans, true)
            HapticFeedback.success()
            lockRefresh += 1
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                quickActions
                floorsNav
                buriedNav

                if service.scans.isEmpty {
                    emptyState
                } else if !searchText.isEmpty && filteredScans.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                } else {
                    scansGrid
                }

                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Plans & 3D")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .floatingSpeedDial(.blueprints)
        .fullScreenCover(isPresented: $showRoomScan) {
            RoomScanView { url in
                showRoomScan = false
                if let url {
                    let name = defaultScanName()
                    service.addScanFile(name: name, kind: "room3d", sourceURL: url, format: "usdz")
                    HapticFeedback.success()
                    pendingZoneName = name
                    showSaveAsZone = true
                }
            }
        }
        .alert("Add to Digital Twin?", isPresented: $showSaveAsZone) {
            TextField("Zone name", text: $pendingZoneName)
            Button("Add as Zone") { saveZoneFromScan() }
            Button("Skip", role: .cancel) { showSaveAsZone = false }
        } message: {
            Text("Link this 3D scan to a new zone in your Digital Twin.")
        }
        .sheet(isPresented: $showAddPlan) {
            AddPlanSheet { name, kind, data, ext, format in
                service.addScanData(name: name, kind: kind, data: data, ext: ext, format: format)
                HapticFeedback.success()
            }
        }
        .sheet(item: $previewItem) { item in
            QuickLookSheet(url: service.fileURL(item.fileName), title: item.name)
        }
        .alert("Rename", isPresented: Binding(
            get: { renameItem != nil },
            set: { if !$0 { renameItem = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let item = renameItem, !renameText.isEmpty {
                    service.renameScan(item, to: renameText)
                }
                renameItem = nil
            }
            Button("Cancel", role: .cancel) { renameItem = nil }
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            QuickActionButton(
                icon: "cube.transparent.fill",
                title: "Scan 3D",
                subtitle: RoomCaptureSession.isSupported ? "LiDAR room scan" : "Needs LiDAR",
                colors: [.purple, .blue]
            ) {
                HapticFeedback.impact(.medium)
                showRoomScan = true
            }

            QuickActionButton(
                icon: "doc.badge.plus",
                title: "Add Plan",
                subtitle: "Photo · PDF",
                colors: [.blue, .teal]
            ) {
                HapticFeedback.impact(.medium)
                showAddPlan = true
            }
        }
    }

    private var floorsNav: some View {
        NavigationLink {
            FloorPlansView()
        } label: {
            GlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Image(systemName: "square.3.layers.3d")
                            .font(AppFont.title3)
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("floors_title")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text("floors_subtitle")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var buriedNav: some View {
        NavigationLink {
            BuriedUtilitiesView(service: service)
        } label: {
            GlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .brown], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .font(AppFont.title3)
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Underground Map")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text("Cables, pipes & buried lines — depth & location")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                    Spacer()
                    if !service.utilities.isEmpty {
                        Text("\(service.utilities.count)")
                            .font(AppFont.scaled(13, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var filteredScans: [HomeScan] {
        service.scans.filter { $0.name.matchesSearch(searchText) }
    }

    private var scansGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            let _ = lockRefresh   // re-render badges when a lock toggles
            Text("SAVED PLANS & MODELS")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filteredScans) { scan in
                    let locked = ItemLockStore.isLocked(scan.id.uuidString, in: .plans)
                    ScanCard(scan: scan, thumbnail: service.image(for: scan))
                        .overlay(alignment: .topTrailing) {
                            if locked {
                                Image(systemName: "lock.fill")
                                    .font(AppFont.label)
                                    .foregroundStyle(.teal)
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .padding(AppSpacing.xs)
                            }
                        }
                        .onTapGesture { withLockCheck(scan) { previewItem = scan } }
                        .contextMenu {
                            Button {
                                withLockCheck(scan) {
                                    renameText = scan.name
                                    renameItem = scan
                                }
                            } label: { Label("Rename", systemImage: "pencil") }
                            Button { toggleLock(scan) } label: {
                                Label(locked ? "Remove Face ID lock" : "Lock with Face ID",
                                      systemImage: locked ? "lock.open" : "lock")
                            }
                            Button(role: .destructive) {
                                HapticFeedback.warning()
                                service.deleteScan(scan)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "ruler.fill",
            title: "No plans yet",
            message: "Scan a room in 3D, or add floor plans and blueprints (photo or PDF) so you always know how your home is built."
        )
    }

    private func defaultScanName() -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"
        return "\(String(localized: "Scan")) \(f.string(from: Date()))"
    }

    private func saveZoneFromScan() {
        guard let propertyId = propertyService.primary?.id else { return }
        let name = pendingZoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewPropertyZone(
            propertyId: propertyId,
            name: name,
            icon: "cube.fill",
            colorHex: "#5E5CE6",
            layer: "indoor",
            healthScore: 80,
            polygon: [],
            sortOrder: zoneService.zones.count,
            createdAt: now,
            updatedAt: now
        )
        Task { await zoneService.add(payload) }
        HapticFeedback.success()
    }
}
