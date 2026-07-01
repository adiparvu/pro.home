import SwiftUI
import RoomPlan
import PhotosUI
import UniformTypeIdentifiers

struct BlueprintsView: View {
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var zoneService: PropertyZoneService
    @StateObject private var service = BlueprintService()
    @State private var showRoomScan = false
    @State private var showAddPlan = false
    @State private var previewItem: HomeScan?
    @State private var renameItem: HomeScan?
    @State private var renameText = ""
    @State private var showSaveAsZone = false
    @State private var pendingZoneName = ""

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                quickActions
                buriedNav

                if service.scans.isEmpty {
                    emptyState
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
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                    Spacer()
                    if !service.utilities.isEmpty {
                        Text("\(service.utilities.count)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var scansGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVED PLANS & MODELS")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(service.scans) { scan in
                    ScanCard(scan: scan, thumbnail: service.image(for: scan))
                        .onTapGesture { previewItem = scan }
                        .contextMenu {
                            Button {
                                renameText = scan.name
                                renameItem = scan
                            } label: { Label("Rename", systemImage: "pencil") }
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
        VStack(spacing: 12) {
            Spacer(minLength: 30)
            Image(systemName: "ruler.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color.primary.opacity(0.16))
            Text("No plans yet")
                .font(AppFont.headline)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text("Scan a room in 3D, or add floor plans and blueprints (photo or PDF) so you always know how your home is built.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer(minLength: 30)
        }
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
