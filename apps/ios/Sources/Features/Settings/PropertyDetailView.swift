import SwiftUI
import PhotosUI

struct PropertyDetailView: View {
    let propertyId: UUID
    @EnvironmentObject private var propertyService: PropertyService

    @State private var showEdit = false
    @State var showPhotoMenu = false
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var pickerItem: PhotosPickerItem?
    @State var isUploadingPhoto = false

    private var property: PropertyModel? {
        propertyService.properties.first { $0.id == propertyId }
    }

    var body: some View {
        Group {
            if let property {
                mainContent(property)
            } else {
                ContentUnavailableView("Property not found", systemImage: "house.slash")
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let property {
                EditPropertySheet(property: property) { updated in
                    await propertyService.update(updated)
                }
                .environmentObject(propertyService)
            }
        }
        .confirmationDialog("Property photo", isPresented: $showPhotoMenu, titleVisibility: .visible) {
            Button("Take a photo") { showCamera = true }
            Button("Choose from gallery") { showGallery = true }
            if property?.photoUrl != nil {
                Button("Delete photo", role: .destructive) {
                    Task { await removePhoto() }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            PropertyCameraPickerView { image in Task { await upload(image) } }
        }
        .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            Task {
                if let item,
                   let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await upload(image)
                }
            }
        }
    }

    private func upload(_ image: UIImage) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        await propertyService.uploadPhoto(propertyId: propertyId, image: image)
    }

    private func removePhoto() async {
        guard var property else { return }
        property.photoUrl = nil
        await propertyService.update(property)
    }
}
