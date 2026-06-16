import SwiftUI
import RoomPlan
import PhotosUI
import UniformTypeIdentifiers

struct BlueprintsView: View {
    @StateObject private var service = BlueprintService()
    @State private var showRoomScan = false
    @State private var showAddPlan = false
    @State private var previewItem: HomeScan?
    @State private var renameItem: HomeScan?
    @State private var renameText = ""

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
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Plans & 3D")
        .navigationBarTitleDisplayMode(.large)
        .floatingSpeedDial(.blueprints)
        .fullScreenCover(isPresented: $showRoomScan) {
            RoomScanView { url in
                showRoomScan = false
                if let url {
                    service.addScanFile(name: defaultScanName(), kind: "room3d", sourceURL: url, format: "usdz")
                    HapticFeedback.success()
                }
            }
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
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [.orange, .brown], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Underground Map")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Cables, pipes & buried lines — depth & location")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.45))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text("Scan a room in 3D, or add floor plans and blueprints (photo or PDF) so you always know how your home is built.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer(minLength: 30)
        }
    }

    private func defaultScanName() -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"
        return "Scan \(f.string(from: Date()))"
    }
}
