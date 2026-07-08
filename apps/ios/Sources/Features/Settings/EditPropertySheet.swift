import SwiftUI
import MapKit
import CoreLocation

// MARK: - Edit Property Sheet

struct EditPropertySheet: View {
    @Environment(\.dismiss) var dismiss
    let property: PropertyModel
    let onSave: (PropertyModel) async -> Void

    @State var name: String
    @State var addressLine1: String
    @State var city: String
    @State var postalCode: String
    @State var country: String
    @State var propertyType: String
    @State var sizeSqmText: String
    @State var numRoomsText: String
    @State var isSaving = false

    @State var yearBuiltText: String
    @State var story: String
    @State var renovations: [Renovation]
    @State var owners: [OwnerRecord]

    @State var showRenovationForm = false
    @State var newRenTitle = ""
    @State var newRenFrom = ""
    @State var newRenTo = ""

    @State var showOwnerForm = false
    @State var newOwnerName = ""
    @State var newOwnerFrom = ""
    @State var newOwnerTo = ""

    @State var latitude: Double?
    @State var longitude: Double?
    @State var latText: String = ""
    @State var lonText: String = ""
    @State var showMap = false
    @State var mapPosition: MapCameraPosition = .automatic
    @State var isLocating = false

    private let propertyTypes = ["apartment", "house", "villa", "studio", "commercial", "other"]

    init(property: PropertyModel, onSave: @escaping (PropertyModel) async -> Void) {
        self.property = property
        self.onSave = onSave
        _name = State(initialValue: property.name)
        _addressLine1 = State(initialValue: property.addressLine1)
        _city = State(initialValue: property.city)
        _postalCode = State(initialValue: property.postalCode ?? "")
        _country = State(initialValue: property.country)
        _propertyType = State(initialValue: property.propertyType)
        _sizeSqmText = State(initialValue: property.sizeSqm.map { String(format: "%.0f", $0) } ?? "")
        _numRoomsText = State(initialValue: property.numRooms.map { "\($0)" } ?? "")
        _yearBuiltText = State(initialValue: property.yearBuilt.map { "\($0)" } ?? "")
        _story = State(initialValue: property.story ?? "")
        _renovations = State(initialValue: property.renovations ?? [])
        _owners = State(initialValue: property.owners ?? [])
        _latitude = State(initialValue: property.latitude)
        _longitude = State(initialValue: property.longitude)
        _latText = State(initialValue: property.latitude.map { String(format: "%.6f", $0) } ?? "")
        _lonText = State(initialValue: property.longitude.map { String(format: "%.6f", $0) } ?? "")
        if let lat = property.latitude, let lon = property.longitude {
            _mapPosition = State(initialValue: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        formFieldGroup { formFieldRow("house.fill", "Property name", $name) }

                        AddressAutocompleteField(
                            addressLine1: $addressLine1,
                            city: $city,
                            postalCode: $postalCode,
                            country: $country,
                            latitude: $latitude,
                            longitude: $longitude,
                            onPicked: {
                                if let lat = latitude, let lon = longitude {
                                    latText = String(format: "%.6f", lat)
                                    lonText = String(format: "%.6f", lon)
                                    mapPosition = .region(MKCoordinateRegion(
                                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
                                    if !showMap { showMap = true }
                                }
                            }
                        )
                        .padding(.top, AppSpacing.lg)

                        mapToggleButton.padding(.top, AppSpacing.md)
                        if showMap { mapPickerSection.padding(.top, AppSpacing.sm) }

                        Text("TYPE")
                            .font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, AppSpacing.xxs).padding(.top, AppSpacing.xl).padding(.bottom, AppSpacing.sm)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(propertyTypes, id: \.self) { type in
                                    Button { propertyType = type } label: {
                                        Text(LocalizedStringKey(type.capitalized))
                                            .font(AppFont.scaled(13, weight: propertyType == type ? .semibold : .regular))
                                            .foregroundStyle(propertyType == type ? Color.black : Color.primary.opacity(AppOpacity.emphasis))
                                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                                            .background(propertyType == type ? Color.white : Color.primary.opacity(0.08), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        formFieldGroup {
                            formFieldRow("ruler.fill", "Area (m²)", $sizeSqmText, keyboard: .decimalPad)
                            formDivider()
                            formFieldRow("door.left.hand.open", "Rooms", $numRoomsText, keyboard: .numberPad)
                            formDivider()
                            formFieldRow("calendar.badge.clock", "Year built", $yearBuiltText, keyboard: .numberPad)
                        }
                        .padding(.top, AppSpacing.lg)

                        storySection
                        renovationsSection
                        ownersSection
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm).padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Property").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.accentColor) }
                        else { Text("Save").font(AppFont.subheadline).foregroundStyle(name.isEmpty || addressLine1.isEmpty ? Color.primary.opacity(0.3) : Color.accentColor) }
                    }
                    .disabled(name.isEmpty || addressLine1.isEmpty || isSaving)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }
}
