import SwiftUI
import UIKit
import PhotosUI

// MARK: - Critical places (device-local)
//
// A critical place is written by the household ahead of time ("water valve —
// behind the washing machine") and read in panic. The note lives in
// UserDefaults and its photo on disk, keyed by the note id — everything works
// with zero connectivity, which is the whole point of this page.

struct EmergencyNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var detail: String
}

// MARK: - Local photo store
//
// Same pattern as InventoryImageStore: one JPEG per note id in the app's
// Documents directory. Camera output is downscaled before writing so panic-time
// loads decode a ~1600px image, not a 12MP original.

enum EmergencyPlaceImageStore {
    private static func url(for id: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("emergency_place_\(id.uuidString).jpg")
    }

    static func save(_ image: UIImage, for id: UUID) {
        guard let jpg = downscaled(image).jpegData(compressionQuality: 0.78) else { return }
        try? jpg.write(to: url(for: id))
    }

    static func load(for id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return UIImage(data: data)
    }

    static func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat = 1600) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// What happened to the place's photo inside the edit sheet. The sheet never
/// touches the store itself — the owner applies the change under the final
/// note id (new notes mint their id at save time).
enum EmergencyPlacePhotoChange {
    case unchanged
    case set(UIImage)
    case removed
}

// MARK: - Add / edit sheet

struct EmergencyNoteSheet: View {
    var editing: EmergencyNote? = nil
    let onSave: (EmergencyNote, EmergencyPlacePhotoChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""
    @State private var photo: UIImage? = nil
    @State private var photoChange: EmergencyPlacePhotoChange = .unchanged
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "emergency_note_title_ph"), text: $title)
                    TextField(String(localized: "emergency_note_detail_ph"), text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("emergency_note_footer")
                }

                Section {
                    if let photo {
                        HStack {
                            Spacer()
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 180, height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                            Spacer()
                        }
                        Button(role: .destructive) {
                            self.photo = nil
                            photoChange = .removed
                        } label: {
                            Label("emg_place_photo_remove", systemImage: "trash")
                        }
                    } else {
                        Button {
                            showCamera = true
                        } label: {
                            Label("emg_place_photo_camera", systemImage: "camera.fill")
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("emg_place_photo_library", systemImage: "photo.on.rectangle")
                        }
                    }
                } header: {
                    Text("emg_place_photo_header")
                } footer: {
                    Text("emg_place_photo_footer")
                }
            }
            .navigationTitle(Text(editing == nil ? "emergency_add_place" : "emergency_edit_place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var note = editing ?? EmergencyNote(title: "", detail: "")
                        note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        note.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(note, photoChange)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    title = editing.title
                    detail = editing.detail
                    photo = EmergencyPlaceImageStore.load(for: editing.id)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { img in
                photo = img
                photoChange = .set(img)
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    photo = img
                    photoChange = .set(img)
                }
                pickerItem = nil
            }
        }
    }
}

// MARK: - Fullscreen photo (local image, offline)

struct EmergencyPhotoItem: Identifiable {
    let id = UUID()
    let title: String
    let image: UIImage
}

struct EmergencyPhotoViewer: View {
    let title: String
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var zoomed = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoomed ? 2.2 : 1)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) { zoomed.toggle() }
                }
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(30))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(AppSpacing.lg)
            }
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(Color.black.opacity(0.5), in: Capsule())
                .padding(.bottom, AppSpacing.xxl)
        }
    }
}
