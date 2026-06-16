import SwiftUI

// MARK: - PlantDetailSheet

struct PlantDetailSheet: View {
    @EnvironmentObject var plantService: PlantService
    @Environment(\.dismiss) var dismiss

    let plant: Plant

    @State var isEditing = false
    @State var editedPlant: Plant
    @State var isSaving = false

    init(plant: Plant) {
        self.plant = plant
        _editedPlant = State(initialValue: plant)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard

                        if isEditing {
                            editFields
                        } else {
                            viewFields
                            waterButton
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(plant.name)
            .navigationBarTitleDisplayMode(.inline)
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
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .disabled(editedPlant.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    } else {
                        Button {
                            withAnimation { isEditing = true }
                        } label: {
                            Text("Edit")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }
}
