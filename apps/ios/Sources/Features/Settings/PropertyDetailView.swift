import SwiftUI
import PhotosUI

struct PropertyDetailView: View {
    let propertyId: UUID
    // Internal (not private): the section builders in
    // PropertyDetailViewComponents.swift read these too.
    @Environment(PropertyService.self) var propertyService
    @Environment(PropertyElementService.self) var elementService

    @State private var showEdit = false
    @State var showPhotoMenu = false
    /// The health-score row opens the existing dashboard (active property).
    @State var showHealthDashboard = false
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var pickerItem: PhotosPickerItem?
    @State var isUploadingPhoto = false

    // Stretchy-hero chrome (driven from PropertyDetailViewComponents).
    /// 0…1 — how far the compact inline bar has materialized.
    @State var heroBarProgress: CGFloat = 0
    /// Measured status-bar + navigation-bar height; the compact bar's frame.
    @State var heroTopInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion

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
        // The hero owns the top of the screen: the system bar never draws its
        // own background (it would fade in on the first scrolled point);
        // the compact bar in mainContent materializes at the title threshold
        // instead, exactly like TestFlight.
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "pencil")
                        .font(AppFont.subheadline)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                        // Legible over the photo pre-26; on iOS 26 the system
                        // wraps toolbar items in Liquid Glass already.
                        .chatToolbarCapsule()
                }
                .accessibilityLabel("Edit property")
            }
        }
        .sheet(isPresented: $showEdit) {
            if let property {
                EditPropertySheet(property: property) { updated in
                    await propertyService.update(updated)
                }
                .environment(propertyService)
            }
        }
        .sheet(isPresented: $showHealthDashboard) {
            // The same route Spaces/Twin/Map present; its services are
            // app-wide. The elements feed the score — make sure they exist
            // before the dashboard reads them.
            PropertyHealthDashboardView()
                .task {
                    if elementService.elements.isEmpty {
                        await elementService.load(propertyId: propertyId)
                    }
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
