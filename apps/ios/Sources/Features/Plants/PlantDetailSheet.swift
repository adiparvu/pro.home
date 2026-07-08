import SwiftUI
import PhotosUI

// MARK: - PlantDetailSheet

struct PlantDetailSheet: View {
    @Environment(PlantService.self) var plantService
    @Environment(PropertyService.self) var propertyService
    @Environment(\.dismiss) var dismiss

    let plant: Plant

    @State var isEditing = false
    @State var editedPlant: Plant
    @State var isSaving = false

    // Photo album (P1)
    @State var photoService = PlantPhotoService()
    @State var albumPickerItem: PhotosPickerItem?
    @State var showAlbumCamera = false
    @State var isUploadingPhoto = false

    // Botanical profile / encyclopedia (P2). Loaded lazily and locally so the
    // card is self-contained — no app-wide wiring, matching photoService.
    @State var speciesService = PlantSpeciesService()
    @State var showSpeciesPicker = false

    init(plant: Plant) {
        self.plant = plant
        _editedPlant = State(initialValue: plant)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard

                        if isEditing {
                            editFields
                            generalInfoEditFields
                        } else {
                            viewFields
                            generalInfoCard
                            botanicalProfileCard
                            photoAlbumCard
                            waterButton
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle(plant.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await photoService.load(plantId: plant.id) }
            .task { await speciesService.loadAll() }
            .sheet(isPresented: $showSpeciesPicker) {
                PlantSpeciesPickerView(service: speciesService) { picked in
                    Task { await plantService.linkSpecies(picked.id, for: plant) }
                }
            }
            .fullScreenCover(isPresented: $showAlbumCamera) {
                CameraCapture { image in Task { await addAlbumPhoto(image) } }
                    .ignoresSafeArea()
            }
            .onChange(of: albumPickerItem) { _, item in
                guard let item else { return }
                Task {
                    defer { albumPickerItem = nil }
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await addAlbumPhoto(img)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Cancel") {
                            editedPlant = plant
                            withAnimation { isEditing = false }
                        }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button {
                            save()
                        } label: {
                            if isSaving {
                                ProgressView().tint(.accentColor)
                            } else {
                                Text("Save")
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .disabled(editedPlant.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    } else {
                        Button {
                            withAnimation { isEditing = true }
                        } label: {
                            Text("Edit")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    func addAlbumPhoto(_ image: UIImage) async {
        guard let pid = propertyService.primary?.id else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        if await photoService.add(image: image, plantId: plant.id, propertyId: pid, note: nil) {
            HapticFeedback.success()
        } else {
            HapticFeedback.error()
        }
    }
}
