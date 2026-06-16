import SwiftUI
import MapKit
import CoreLocation

// MARK: - Address Autocomplete

@MainActor
final class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func query(_ text: String) { completer.queryFragment = text }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError _: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}

// MARK: - Shared form helpers

func formFieldGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
}

func formFieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28)
        TextField(placeholder, text: binding)
            .font(.system(size: 15))
            .foregroundStyle(.primary)
            .tint(.accentColor)
            .keyboardType(keyboard)
    }
    .padding(.horizontal, 16).padding(.vertical, 13)
}

func formDivider() -> some View {
    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
}

func formCoordField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.4))
        TextField(placeholder, text: text)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(.primary)
            .tint(.accentColor)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .frame(maxWidth: .infinity)
}

// MARK: - Edit Property Sheet

struct EditPropertySheet: View {
    @Environment(\.dismiss) private var dismiss
    let property: PropertyModel
    let onSave: (PropertyModel) async -> Void

    @State private var name: String
    @State private var addressLine1: String
    @State private var city: String
    @State private var postalCode: String
    @State private var country: String
    @State private var propertyType: String
    @State private var sizeSqmText: String
    @State private var numRoomsText: String
    @State private var isSaving = false

    @State private var yearBuiltText: String
    @State private var story: String
    @State private var renovations: [Renovation]
    @State private var owners: [OwnerRecord]

    @State private var showRenovationForm = false
    @State private var newRenTitle = ""
    @State private var newRenFrom = ""
    @State private var newRenTo = ""

    @State private var showOwnerForm = false
    @State private var newOwnerName = ""
    @State private var newOwnerFrom = ""
    @State private var newOwnerTo = ""

    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var latText: String = ""
    @State private var lonText: String = ""
    @State private var showMap = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isLocating = false

    @StateObject private var completer = AddressCompleter()
    @State private var showSuggestions = false
    @FocusState private var addressFocused: Bool

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

    // MARK: - Sub-sections

    private var suggestionDropdown: some View {
        VStack(spacing: 0) {
            ForEach(completer.suggestions.prefix(4), id: \.title) { s in
                Button { applySuggestion(s) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                            if !s.subtitle.isEmpty { Text(s.subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5)) }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if s.title != completer.suggestions.prefix(4).last?.title { Divider().padding(.leading, 44) }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .padding(.top, 4)
    }

    private var mapToggleButton: some View {
        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showMap.toggle() } } label: {
            HStack {
                Image(systemName: "map.fill").foregroundStyle(Color.accentColor)
                Text("Location on map").font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: showMap ? "chevron.up" : "chevron.down").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                if latitude != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 14)) }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var mapPickerSection: some View {
        ZStack {
            Map(position: $mapPosition)
                .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onMapCameraChange { ctx in
                    latitude = ctx.camera.centerCoordinate.latitude
                    longitude = ctx.camera.centerCoordinate.longitude
                    latText = String(format: "%.6f", ctx.camera.centerCoordinate.latitude)
                    lonText = String(format: "%.6f", ctx.camera.centerCoordinate.longitude)
                }
            VStack(spacing: 0) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.red).shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Image(systemName: "triangle.fill").font(.system(size: 7)).foregroundStyle(.red).rotationEffect(.degrees(180)).offset(y: -3)
                Spacer()
            }.padding(.top, 46)
            VStack { Spacer(); HStack {
                Button { Task { await reverseGeocode() } } label: {
                    Label("Apply address", systemImage: "arrow.up.left.square.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 7).background(.blue, in: Capsule())
                }.buttonStyle(.plain).padding(.leading, 10).padding(.bottom, 10)
                Spacer()
                Button { Task { await useCurrentLocation() } } label: {
                    ZStack {
                        Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36)
                        if isLocating { ProgressView().tint(.accentColor).scaleEffect(0.7) }
                        else { Image(systemName: "location.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor) }
                    }
                }.buttonStyle(.plain).padding(.trailing, 10).padding(.bottom, 10)
            }}
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8))

        HStack(spacing: 8) {
            formCoordField("Latitude", text: $latText, placeholder: "e.g. 44.426800")
            formCoordField("Longitude", text: $lonText, placeholder: "e.g. 26.102500")
            Button { applyManualCoords() } label: {
                Image(systemName: "arrow.right.circle.fill").font(.system(size: 28)).foregroundStyle(Color.accentColor)
            }.buttonStyle(.plain)
        }.padding(.top, 8)
    }

    private var storySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STORY").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).padding(.top, 20).padding(.bottom, 0)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                if story.isEmpty {
                    Text("Write a story about this property…").font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.28))
                        .padding(.horizontal, 16).padding(.vertical, 13)
                }
                TextEditor(text: $story).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                    .scrollContentBackground(.hidden).background(.clear).frame(minHeight: 100)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    private var renovationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RENOVATIONS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                Spacer()
                Button { withAnimation { showRenovationForm.toggle() } } label: {
                    Image(systemName: showRenovationForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(Color.accentColor).font(.system(size: 18))
                }.buttonStyle(.plain)
            }.padding(.leading, 4).padding(.top, 20)

            if !renovations.isEmpty {
                VStack(spacing: 0) {
                    ForEach(renovations) { r in
                        HStack(spacing: 10) {
                            Circle().fill(.blue).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.system(size: 14, weight: .medium))
                                Text(r.yearRange).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { renovations.removeAll { $0.id == r.id } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.3))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if r.id != renovations.last?.id {
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 32)
                        }
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            }

            if showRenovationForm {
                VStack(spacing: 8) {
                    formFieldGroup {
                        formFieldRow("wrench.fill", "Renovation title", $newRenTitle)
                        formDivider()
                        formFieldRow("calendar", "Start year", $newRenFrom, keyboard: .numberPad)
                        formDivider()
                        formFieldRow("calendar", "End year (optional)", $newRenTo, keyboard: .numberPad)
                    }
                    Button {
                        guard !newRenTitle.isEmpty, let from = Int(newRenFrom) else { return }
                        renovations.append(Renovation(yearFrom: from, yearTo: Int(newRenTo), title: newRenTitle))
                        newRenTitle = ""; newRenFrom = ""; newRenTo = ""; showRenovationForm = false
                    } label: {
                        Text("Add renovation").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(newRenTitle.isEmpty || newRenFrom.isEmpty ? Color.primary.opacity(0.3) : .blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain).disabled(newRenTitle.isEmpty || newRenFrom.isEmpty)
                }
            }
        }
    }

    private var ownersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("OWNERS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                Spacer()
                Button { withAnimation { showOwnerForm.toggle() } } label: {
                    Image(systemName: showOwnerForm ? "minus.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(Color.accentColor).font(.system(size: 18))
                }.buttonStyle(.plain)
            }.padding(.leading, 4).padding(.top, 20)

            if !owners.isEmpty {
                VStack(spacing: 0) {
                    ForEach(owners) { o in
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(o.name).font(.system(size: 14, weight: .medium))
                                Text(o.yearRange).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { owners.removeAll { $0.id == o.id } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(Color.primary.opacity(0.3))
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if o.id != owners.last?.id {
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 40)
                        }
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            }

            if showOwnerForm {
                VStack(spacing: 8) {
                    formFieldGroup {
                        formFieldRow("person.fill", "Owner name", $newOwnerName)
                        formDivider()
                        formFieldRow("calendar", "Start year", $newOwnerFrom, keyboard: .numberPad)
                        formDivider()
                        formFieldRow("calendar", "End year (optional)", $newOwnerTo, keyboard: .numberPad)
                    }
                    Button {
                        guard !newOwnerName.isEmpty, let from = Int(newOwnerFrom) else { return }
                        owners.append(OwnerRecord(name: newOwnerName, yearFrom: from, yearTo: Int(newOwnerTo)))
                        newOwnerName = ""; newOwnerFrom = ""; newOwnerTo = ""; showOwnerForm = false
                    } label: {
                        Text("Add owner").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(newOwnerName.isEmpty || newOwnerFrom.isEmpty ? Color.primary.opacity(0.3) : .blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain).disabled(newOwnerName.isEmpty || newOwnerFrom.isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private func applySuggestion(_ suggestion: MKLocalSearchCompletion) {
        showSuggestions = false; addressFocused = false
        let req = MKLocalSearch.Request(completion: suggestion)
        Task {
            if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
                let p = item.placemark
                if let t = p.thoroughfare { addressLine1 = t + (p.subThoroughfare.map { " " + $0 } ?? "") }
                city = p.locality ?? p.administrativeArea ?? city
                country = p.countryCode ?? country
                if let pc = p.postalCode, !pc.isEmpty { postalCode = pc }
                latitude = p.coordinate.latitude; longitude = p.coordinate.longitude
                latText = String(format: "%.6f", p.coordinate.latitude)
                lonText = String(format: "%.6f", p.coordinate.longitude)
                mapPosition = .region(MKCoordinateRegion(center: p.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
                if !showMap { showMap = true }
            }
        }
    }

    private func reverseGeocode() async {
        guard let lat = latitude, let lon = longitude else { return }
        if let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first {
            if let t = p.thoroughfare { addressLine1 = t + (p.subThoroughfare.map { " " + $0 } ?? "") }
            if let l = p.locality { city = l }
            if let pc = p.postalCode, !pc.isEmpty { postalCode = pc }
            if let cc = p.isoCountryCode { country = cc }
        }
    }

    private func useCurrentLocation() async {
        isLocating = true; defer { isLocating = false }
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        if let loc = mgr.location {
            latitude = loc.coordinate.latitude; longitude = loc.coordinate.longitude
            mapPosition = .region(MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
            if !showMap { showMap = true }
            await reverseGeocode()
        }
    }

    private func applyManualCoords() {
        guard let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
              let lon = Double(lonText.replacingOccurrences(of: ",", with: ".")) else { return }
        latitude = lat; longitude = lon
        mapPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        if !showMap { showMap = true }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        var updated = property
        updated.name = name; updated.addressLine1 = addressLine1; updated.city = city
        updated.country = country; updated.propertyType = propertyType
        updated.postalCode = postalCode.isEmpty ? nil : postalCode
        updated.sizeSqm = Double(sizeSqmText); updated.numRooms = Int(numRoomsText)
        updated.latitude = latitude; updated.longitude = longitude
        updated.yearBuilt = Int(yearBuiltText)
        updated.story = story.isEmpty ? nil : story
        updated.renovations = renovations; updated.owners = owners
        await onSave(updated); HapticFeedback.success(); dismiss()
    }
}

// MARK: - Add Property Sheet

struct AddPropertySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var propertyService: PropertyService

    @State private var name = ""
    @State private var addressLine1 = ""
    @State private var city = ""
    @State private var postalCode = ""
    @State private var country = "RO"
    @State private var propertyType = "apartment"
    @State private var sizeSqmText = ""
    @State private var numRoomsText = ""
    @State private var isSaving = false

    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var latText = ""
    @State private var lonText = ""
    @State private var showMap = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isLocating = false

    @StateObject private var completer = AddressCompleter()
    @State private var showSuggestions = false
    @FocusState private var addressFocused: Bool

    private let propertyTypes = ["apartment", "house", "villa", "studio", "commercial", "other"]

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
                                }.padding(.horizontal, 16).padding(.vertical, 13)
                                formDivider()
                                formFieldRow("building.2.fill", "City", $city)
                                formDivider()
                                formFieldRow("envelope.fill", "Postal code", $postalCode, keyboard: .numbersAndPunctuation)
                                formDivider()
                                formFieldRow("globe.europe.africa.fill", "Country", $country)
                            }
                            if showSuggestions && !completer.suggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(completer.suggestions.prefix(4), id: \.title) { s in
                                        Button { applySuggestion(s) } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "mappin.circle.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(s.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                                    if !s.subtitle.isEmpty { Text(s.subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5)) }
                                                }
                                                Spacer()
                                            }.padding(.horizontal, 16).padding(.vertical, 10)
                                        }.buttonStyle(.plain)
                                        if s.title != completer.suggestions.prefix(4).last?.title { Divider().padding(.leading, 44) }
                                    }
                                }
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                                .padding(.top, 4)
                            }
                        }.padding(.top, 16)

                        Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showMap.toggle() } } label: {
                            HStack {
                                Image(systemName: "map.fill").foregroundStyle(Color.accentColor)
                                Text("Location on map").font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: showMap ? "chevron.up" : "chevron.down").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                                if latitude != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 14)) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                        }.buttonStyle(.plain).padding(.top, 12)

                        if showMap { mapPickerSection.padding(.top, 8) }

                        Text("TYPE").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).padding(.top, 20).padding(.bottom, 8)
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
                        }.padding(.top, 16)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                }
                .onTapGesture { if showSuggestions { showSuggestions = false }; addressFocused = false }
            }
            .navigationTitle("Add Property").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.accentColor) }
                        else { Text("Add").font(.system(size: 15, weight: .semibold)).foregroundStyle(name.isEmpty || addressLine1.isEmpty ? Color.primary.opacity(0.3) : Color.accentColor) }
                    }.disabled(name.isEmpty || addressLine1.isEmpty || isSaving)
                }
            }
        }
    }

    private var mapPickerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Map(position: $mapPosition).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onMapCameraChange { ctx in
                        latitude = ctx.camera.centerCoordinate.latitude; longitude = ctx.camera.centerCoordinate.longitude
                        latText = String(format: "%.6f", ctx.camera.centerCoordinate.latitude)
                        lonText = String(format: "%.6f", ctx.camera.centerCoordinate.longitude)
                    }
                VStack(spacing: 0) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.red).shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    Image(systemName: "triangle.fill").font(.system(size: 7)).foregroundStyle(.red).rotationEffect(.degrees(180)).offset(y: -3)
                    Spacer()
                }.padding(.top, 46)
                VStack { Spacer(); HStack {
                    Button { Task { await reverseGeocode() } } label: {
                        Label("Apply address", systemImage: "arrow.up.left.square.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 7).background(.blue, in: Capsule())
                    }.buttonStyle(.plain).padding(.leading, 10).padding(.bottom, 10)
                    Spacer()
                    Button { Task { await useCurrentLocation() } } label: {
                        ZStack {
                            Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36)
                            if isLocating { ProgressView().tint(.accentColor).scaleEffect(0.7) }
                            else { Image(systemName: "location.fill").font(.system(size: 14)).foregroundStyle(Color.accentColor) }
                        }
                    }.buttonStyle(.plain).padding(.trailing, 10).padding(.bottom, 10)
                }}
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8))

            HStack(spacing: 8) {
                formCoordField("Latitude", text: $latText, placeholder: "e.g. 44.426800")
                formCoordField("Longitude", text: $lonText, placeholder: "e.g. 26.102500")
                Button { applyManualCoords() } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                }.buttonStyle(.plain)
            }
        }
    }

    private func applySuggestion(_ suggestion: MKLocalSearchCompletion) {
        showSuggestions = false; addressFocused = false
        let req = MKLocalSearch.Request(completion: suggestion)
        Task {
            if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
                let p = item.placemark
                if let t = p.thoroughfare { addressLine1 = t + (p.subThoroughfare.map { " " + $0 } ?? "") }
                city = p.locality ?? p.administrativeArea ?? city
                country = p.countryCode ?? country
                if let pc = p.postalCode, !pc.isEmpty { postalCode = pc }
                latitude = p.coordinate.latitude; longitude = p.coordinate.longitude
                latText = String(format: "%.6f", p.coordinate.latitude)
                lonText = String(format: "%.6f", p.coordinate.longitude)
                mapPosition = .region(MKCoordinateRegion(center: p.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
                if !showMap { showMap = true }
            }
        }
    }

    private func reverseGeocode() async {
        guard let lat = latitude, let lon = longitude else { return }
        if let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first {
            if let t = p.thoroughfare { addressLine1 = t + (p.subThoroughfare.map { " " + $0 } ?? "") }
            if let l = p.locality { city = l }
            if let pc = p.postalCode, !pc.isEmpty { postalCode = pc }
            if let cc = p.isoCountryCode { country = cc }
        }
    }

    private func useCurrentLocation() async {
        isLocating = true; defer { isLocating = false }
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        if let loc = mgr.location {
            latitude = loc.coordinate.latitude; longitude = loc.coordinate.longitude
            mapPosition = .region(MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
            if !showMap { showMap = true }
            await reverseGeocode()
        }
    }

    private func applyManualCoords() {
        guard let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
              let lon = Double(lonText.replacingOccurrences(of: ",", with: ".")) else { return }
        latitude = lat; longitude = lon
        mapPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        if !showMap { showMap = true }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        await propertyService.create(
            name: name, addressLine1: addressLine1, city: city, country: country,
            propertyType: propertyType, postalCode: postalCode.isEmpty ? nil : postalCode,
            sizeSqm: Double(sizeSqmText), numRooms: Int(numRoomsText),
            latitude: latitude, longitude: longitude
        )
        if propertyService.error == nil { HapticFeedback.success(); dismiss() }
    }
}
