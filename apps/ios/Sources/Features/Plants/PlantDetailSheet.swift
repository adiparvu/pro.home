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

    // Care requirements + live sensor comparison (P3). Bindings loaded lazily
    // and locally, like the other plant-page services.
    @State var plantSensorService = PlantSensorService()

    // Care history timeline (P5). Loaded lazily and locally, like the other
    // plant-page services; feeds the History surface's quick actions + timeline.
    @State var eventService = PlantEventService()

    // Ailments knowledge base + guided diagnosis (P4). Loaded lazily and
    // locally, like the other plant-page services; powers the Health surface.
    @State var ailmentService = PlantAilmentService()

    // Per-plant automations (P6). Loaded lazily and locally; reconciled into
    // the existing IoT automation engine (IoTService) so real sensors drive it.
    @State var automationService = PlantAutomationService()

    // Care-sheet PDF export (mirrors PropertyElementDetailView's export flow).
    @State private var exportURL: ShareURL?

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
                            careCard
                            healthScoreCard
                            healthCard
                            photoAlbumCard
                            PlantHistorySection(
                                plant: plant,
                                plantService: plantService,
                                eventService: eventService,
                                photoService: photoService
                            )
                            automationsCard
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
            .task { await plantSensorService.load(plantId: plant.id) }
            .task { await eventService.load(plantId: plant.id) }
            .task { await ailmentService.loadAll() }
            .task { await automationService.load(plantId: plant.id) }
            .onChange(of: healthSignature) { _, _ in persistHealthScore() }
            .sheet(item: $exportURL) { share in
                ActivityShareView(items: [share.url])
            }
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
                            withAnimation(AppMotion.state) { isEditing = false }
                        }
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !isEditing {
                        Button {
                            exportCareSheet()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel(Text("Export PDF"))
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
                            withAnimation(AppMotion.state) { isEditing = true }
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

    /// Renders the care-sheet PDF off the main actor and presents the share
    /// sheet. Uses the live plant row (so a just-linked species is included),
    /// the already-loaded encyclopedia entry, and the already-loaded history —
    /// no new fetches.
    private func exportCareSheet() {
        let current = plantService.plants.first(where: { $0.id == plant.id }) ?? plant
        let entry = speciesService.species(id: current.speciesId)
        let events = eventService.events
        Task {
            if let url = await Task.detached(priority: .userInitiated, operation: {
                PlantPDFExporter.makePDF(for: current, species: entry, events: events)
            }).value {
                exportURL = ShareURL(url: url)
            }
        }
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
