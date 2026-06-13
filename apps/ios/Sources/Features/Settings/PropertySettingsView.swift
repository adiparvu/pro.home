import SwiftUI
import MapKit
import CoreLocation

struct PropertySettingsView: View {
    @EnvironmentObject private var propertyService: PropertyService
    @State private var showEdit = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if let property = propertyService.primary {
                    propertyCard(property)
                    detailsSection(property)
                } else {
                    emptyState
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("My Property")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if propertyService.primary != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { showEdit = true }
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let property = propertyService.primary {
                EditPropertySheet(property: property) { updated in
                    await propertyService.update(updated)
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { propertyService.error != nil },
            set: { if !$0 { propertyService.error = nil } }
        )) {
            Button("OK") { propertyService.error = nil }
        } message: {
            Text(propertyService.error ?? "")
        }
        .task { await propertyService.load() }
    }

    // MARK: - Property card

    private func propertyCard(_ p: PropertyModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                        Image(systemName: "house.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("\(p.addressLine1), \(p.city)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.55))
                        Text(p.propertyType.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                }

                if let score = p.healthScore {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.7))
                        Text("Health Score")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.55))
                        Spacer()
                        Text("\(score)/100")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    // MARK: - Details

    private func detailsSection(_ p: PropertyModel) -> some View {
        SettingsGroup(title: "Details") {
            PropDetailRow(label: "Address", value: p.addressLine1)
            PropDetailRow(label: "City", value: p.city)
            PropDetailRow(label: "Country", value: p.country)
            PropDetailRow(label: "Type", value: p.propertyType.capitalized)
            if let sqm = p.sizeSqm {
                PropDetailRow(label: "Area", value: String(format: "%.0f m²", sqm))
            }
            if let rooms = p.numRooms {
                PropDetailRow(label: "Rooms", value: "\(rooms)")
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "house.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text("No property found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.55))
            Text("Your property data will appear here once it's configured.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.38))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Address Completer

@MainActor
private final class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func query(_ text: String) {
        completer.queryFragment = text
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in self.suggestions = results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError _: Error) {
        Task { @MainActor in self.suggestions = [] }
    }
}

// MARK: - Edit sheet

private struct EditPropertySheet: View {
    @Environment(\.dismiss) private var dismiss
    let property: PropertyModel
    let onSave: (PropertyModel) async -> Void

    @State private var name: String
    @State private var addressLine1: String
    @State private var city: String
    @State private var country: String
    @State private var propertyType: String
    @State private var sizeSqmText: String
    @State private var numRoomsText: String
    @State private var isSaving = false

    // Location
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var showMap = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isLocating = false

    // Autocomplete
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
        _country = State(initialValue: property.country)
        _propertyType = State(initialValue: property.propertyType)
        _sizeSqmText = State(initialValue: property.sizeSqm.map { String(format: "%.0f", $0) } ?? "")
        _numRoomsText = State(initialValue: property.numRooms.map { "\($0)" } ?? "")
        _latitude = State(initialValue: property.latitude)
        _longitude = State(initialValue: property.longitude)
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
                        // Name field
                        fieldGroup {
                            fieldRow("house.fill", "Property name", $name)
                        }

                        // Address fields + autocomplete
                        VStack(spacing: 0) {
                            fieldGroup {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.blue)
                                        .frame(width: 28)
                                    TextField("Address", text: $addressLine1)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.primary)
                                        .tint(.blue)
                                        .focused($addressFocused)
                                        .onChange(of: addressLine1) { _, val in
                                            completer.query(val + " " + city)
                                            showSuggestions = !val.isEmpty
                                        }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                divider
                                fieldRow("building.2.fill", "City", $city)
                                divider
                                fieldRow("globe.europe.africa.fill", "Country", $country)
                            }

                            // Suggestions dropdown
                            if showSuggestions && !completer.suggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(completer.suggestions.prefix(4), id: \.title) { s in
                                        Button {
                                            applySuggestion(s)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(.blue)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(s.title)
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(.primary)
                                                    if !s.subtitle.isEmpty {
                                                        Text(s.subtitle)
                                                            .font(.system(size: 12))
                                                            .foregroundStyle(Color.primary.opacity(0.5))
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                        }
                                        .buttonStyle(.plain)
                                        if s.title != completer.suggestions.prefix(4).last?.title {
                                            Divider().padding(.leading, 44)
                                        }
                                    }
                                }
                                .background(Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                                .padding(.top, 4)
                            }
                        }
                        .padding(.top, 16)

                        // Map picker toggle
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showMap.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "map.fill").foregroundStyle(.blue)
                                Text("Localizare pe hartă")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: showMap ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                                if latitude != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.system(size: 14))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)

                        if showMap {
                            mapPickerSection
                                .padding(.top, 8)
                        }

                        // Type selector
                        Text("TYPE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.35))
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
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        fieldGroup {
                            fieldRow("ruler.fill", "Area (m²)", $sizeSqmText, keyboard: .decimalPad)
                            divider
                            fieldRow("door.left.hand.open", "Rooms", $numRoomsText, keyboard: .numberPad)
                        }
                        .padding(.top, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .onTapGesture {
                    if showSuggestions { showSuggestions = false }
                    addressFocused = false
                }
            }
            .navigationTitle("Edit Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving {
                            ProgressView().tint(.blue)
                        } else {
                            Text("Save")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(name.isEmpty || addressLine1.isEmpty ? Color.primary.opacity(0.3) : Color.blue)
                        }
                    }
                    .disabled(name.isEmpty || addressLine1.isEmpty || isSaving)
                }
            }
        }
    }

    // MARK: - Map picker

    private var mapPickerSection: some View {
        ZStack {
            Map(position: $mapPosition)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onMapCameraChange { ctx in
                    latitude = ctx.camera.centerCoordinate.latitude
                    longitude = ctx.camera.centerCoordinate.longitude
                }

            // Center pin (always centered)
            VStack(spacing: 0) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.red)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                    .rotationEffect(.degrees(180))
                    .offset(y: -3)
                Spacer()
            }
            .padding(.top, 46)

            // Controls overlay
            VStack {
                Spacer()
                HStack {
                    // Reverse geocode button
                    Button {
                        Task { await reverseGeocode() }
                    } label: {
                        Label("Aplică adresa", systemImage: "arrow.up.left.square.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 10).padding(.bottom, 10)

                    Spacer()

                    // Current location button
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        ZStack {
                            Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36)
                            if isLocating {
                                ProgressView().tint(.blue).scaleEffect(0.7)
                            } else {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10).padding(.bottom, 10)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
        )
    }

    // MARK: - Helpers

    private func applySuggestion(_ suggestion: MKLocalSearchCompletion) {
        showSuggestions = false
        addressFocused = false
        let req = MKLocalSearch.Request(completion: suggestion)
        Task {
            if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
                let placemark = item.placemark
                if let thoroughfare = placemark.thoroughfare {
                    addressLine1 = thoroughfare + (placemark.subThoroughfare.map { " " + $0 } ?? "")
                }
                city = placemark.locality ?? placemark.administrativeArea ?? city
                country = placemark.countryCode ?? country
                latitude = placemark.coordinate.latitude
                longitude = placemark.coordinate.longitude
                mapPosition = .region(MKCoordinateRegion(
                    center: placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))
                if !showMap { showMap = true }
            }
        }
    }

    private func reverseGeocode() async {
        guard let lat = latitude, let lon = longitude else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        if let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(CLLocation(latitude: coord.latitude, longitude: coord.longitude)).first {
            if let thoroughfare = placemark.thoroughfare {
                addressLine1 = thoroughfare + (placemark.subThoroughfare.map { " " + $0 } ?? "")
            }
            if let locality = placemark.locality { city = locality }
            if let cc = placemark.isoCountryCode { country = cc }
        }
    }

    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        let mgr = CLLocationManager()
        mgr.requestWhenInUseAuthorization()
        if let loc = mgr.location {
            latitude = loc.coordinate.latitude
            longitude = loc.coordinate.longitude
            mapPosition = .region(MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
            if !showMap { showMap = true }
            await reverseGeocode()
        }
    }

    private func fieldGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.blue)
                .frame(width: 28)
            TextField(placeholder, text: binding)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = property
        updated.name = name
        updated.addressLine1 = addressLine1
        updated.city = city
        updated.country = country
        updated.propertyType = propertyType
        updated.sizeSqm = Double(sizeSqmText)
        updated.numRooms = Int(numRoomsText)
        updated.latitude = latitude
        updated.longitude = longitude
        await onSave(updated)
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - Row

private struct PropDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 14)
    }
}
