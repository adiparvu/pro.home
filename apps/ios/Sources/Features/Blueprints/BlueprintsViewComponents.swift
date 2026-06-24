import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Quick action button

struct QuickActionButton: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
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

struct ScanCard: View {
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
                Text(LocalizedStringKey(scan.kindLabel))
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

struct AddPlanSheet: View {
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
        case "floorplan": return String(localized: "Floor Plan")
        case "blueprint": return String(localized: "Blueprint")
        case "site3d":    return String(localized: "Site / Yard")
        case "photo":     return String(localized: "Photo")
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
                    .foregroundStyle(canSave ? Color.accentColor : Color.primary.opacity(0.3))
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
                    .foregroundStyle(Color.accentColor)
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
            Image(systemName: "textformat").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField("Name", text: $name)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
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
                            Text(LocalizedStringKey(kindLabel(k)))
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
