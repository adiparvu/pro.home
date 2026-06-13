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
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    PageHeader(title: "Plans & 3D")

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
        }
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - Quick action button

private struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 110)
            .padding(14)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scan card

private struct ScanCard: View {
    let scan: HomeScan
    let thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [scan.accent.opacity(0.35), scan.accent.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: scan.icon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(scan.accent)
                }
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(scan.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(scan.kindLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(scan.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Add plan sheet

private struct AddPlanSheet: View {
    /// (name, kind, data, fileExtension, format)
    let onSave: (String, String, Data, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind = "floorplan"
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showPDFImporter = false
    @State private var pickedData: Data?
    @State private var pickedExt = ""
    @State private var pickedFormat = ""
    @State private var previewImage: UIImage?

    private let kinds = ["floorplan", "blueprint", "site3d", "photo"]
    private func kindLabel(_ k: String) -> String {
        switch k {
        case "floorplan": return "Floor Plan"
        case "blueprint": return "Blueprint"
        case "site3d":    return "Site / Yard"
        case "photo":     return "Photo"
        default:          return k.capitalized
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        sourcePicker
                        if previewImage != nil || pickedData != nil {
                            filePreview
                        }
                        nameField
                        kindPicker
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Plan").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let data = pickedData, !name.isEmpty else { return }
                        onSave(name, kind, data, pickedExt, pickedFormat)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSave ? Color.blue : Color.primary.opacity(0.3))
                    .disabled(!canSave)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            pickedData = data
                            pickedExt = "jpg"
                            pickedFormat = "image"
                            previewImage = UIImage(data: data)
                            if name.isEmpty { name = "Plan \(shortDate())" }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCapture { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        pickedData = data
                        pickedExt = "jpg"
                        pickedFormat = "image"
                        previewImage = image
                        if name.isEmpty { name = "Plan \(shortDate())" }
                    }
                }
            }
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        pickedData = data
                        pickedExt = "pdf"
                        pickedFormat = "pdf"
                        previewImage = nil
                        if name.isEmpty {
                            name = url.deletingPathExtension().lastPathComponent
                        }
                    }
                }
            }
        }
    }

    private var canSave: Bool { pickedData != nil && !name.isEmpty }

    private var sourcePicker: some View {
        HStack(spacing: 10) {
            sourceButton("photo.on.rectangle", "Photo") { showPhotoPicker = true }
            sourceButton("camera.fill", "Camera") { showCamera = true }
            sourceButton("doc.fill", "PDF") { showPDFImporter = true }
        }
    }

    private func sourceButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var filePreview: some View {
        Group {
            if let img = previewImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "doc.richtext.fill").foregroundStyle(.red).font(.system(size: 22))
                    Text("PDF ready to save").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.7))
                    Spacer()
                }
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
            TextField("Name", text: $name)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORY").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.self) { k in
                        Button { kind = k } label: {
                            Text(kindLabel(k))
                                .font(.system(size: 13, weight: kind == k ? .semibold : .regular))
                                .foregroundStyle(kind == k ? Color.black : Color.primary.opacity(0.7))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(kind == k ? Color.white : Color.primary.opacity(0.08), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func shortDate() -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: Date())
    }
}
