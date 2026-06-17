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

    @StateObject var completer = AddressCompleter()
    @State var showSuggestions = false
    @FocusState var addressFocused: Bool

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
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        formFieldGroup { formFieldRow("house.fill", "Property name", $name) }

                        VStack(spacing: 0) {
                            formFieldGroup {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                    TextField("Address", text: $addressLine1)
                                        .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                                        .focused($addressFocused)
                                        .onChange(of: addressLine1) { _, val in
                                            completer.query(val + " " + city)
                                            showSuggestions = !val.isEmpty
                                        }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                formDivider()
                                formFieldRow("building.2.fill", "City", $city)
                                formDivider()
                                formFieldRow("envelope.fill", "Postal code", $postalCode, keyboard: .numbersAndPunctuation)
                                formDivider()
                                formFieldRow("globe.europe.africa.fill", "Country", $country)
                            }
                            if showSuggestions && !completer.suggestions.isEmpty {
                                suggestionDropdown
                            }
                        }
                        .padding(.top, 16)

                        mapToggleButton.padding(.top, 12)
                        if showMap { mapPickerSection.padding(.top, 8) }

                        Text("TYPE")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4).padding(.top, 20).padding(.bottom, 8)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(propertyTypes, id: \.self) { type in
                                    Button { propertyType = type } label: {
                                        Text(type.capitalized)
                                            .font(.system(size: 13, weight: propertyType == type ? .semibold : .regular))
                                            .foregroundStyle(propertyType == type ? Color.black : Color.primary.opacity(0.7))
                                            .padding(.horizontal, 14).padding(.vertical, 8)
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
                        .padding(.top, 16)

                        storySection
                        renovationsSection
                        ownersSection
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                }
                .onTapGesture { if showSuggestions { showSuggestions = false }; addressFocused = false }
            }
            .navigationTitle("Edit Property").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.accentColor) }
                        else { Text("Save").font(.system(size: 15, weight: .semibold)).foregroundStyle(name.isEmpty || addressLine1.isEmpty ? Color.primary.opacity(0.3) : Color.accentColor) }
                    }
                    .disabled(name.isEmpty || addressLine1.isEmpty || isSaving)
                }
            }
        }
    }
}
