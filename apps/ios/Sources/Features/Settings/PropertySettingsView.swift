import SwiftUI
import MapKit
import CoreLocation
import PhotosUI

struct PropertySettingsView: View {
    @EnvironmentObject private var propertyService: PropertyService
    @State private var showAdd = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if propertyService.properties.isEmpty {
                    emptyState
                } else {
                    ForEach(propertyService.properties) { p in
                        NavigationLink {
                            PropertyDetailView(propertyId: p.id)
                                .environmentObject(propertyService)
                        } label: {
                            propertyCard(p)
                        }
                        .buttonStyle(.plain)
                    }
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPropertySheet()
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

    // MARK: - Property card (list row)

    private func propertyCard(_ p: PropertyModel) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                propertyThumb(p)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("\(p.addressLine1), \(p.city)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(p.propertyType.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue.opacity(0.8))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.blue.opacity(0.15), in: Capsule())
                        if let score = p.healthScore {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(.red.opacity(0.7))
                                Text("\(score)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.6))
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
    }

    @ViewBuilder
    private func propertyThumb(_ p: PropertyModel) -> some View {
        if let urlStr = p.photoUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { thumbPlaceholder }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            thumbPlaceholder.frame(width: 56, height: 56)
        }
    }

    private var thumbPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "house.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
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

    // Rich profile
    @State private var yearBuiltText: String
    @State private var story: String
    @State private var renovations: [Renovation]
    @State private var owners: [OwnerRecord]

    // Add-renovation form
    @State private var showRenovationForm = false
    @State private var newRenTitle = ""
    @State private var newRenFrom = ""
    @State private var newRenTo = ""

    // Add-owner form
    @State private var showOwnerForm = false
    @State private var newOwnerName = ""
    @State private var newOwnerFrom = ""
    @State private var newOwnerTo = ""

    // Location
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var latText: String = ""
    @State private var lonText: String = ""
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
                        // Name field
                        formFieldGroup {
                            formFieldRow("house.fill", "Property name", $name)
                        }

                        // Address fields + autocomplete
                        VStack(spacing: 0) {
                            formFieldGroup {
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
                                formDivider()
                                formFieldRow("building.2.fill", "City", $city)
                                formDivider()
                                formFieldRow("envelope.fill", "Cod poștal", $postalCode, keyboard: .numbersAndPunctuation)
                                formDivider()
                                formFieldRow("globe.europe.africa.fill", "Country", $country)
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

                        formFieldGroup {
                            formFieldRow("ruler.fill", "Area (m²)", $sizeSqmText, keyboard: .decimalPad)
                            formDivider()
                            formFieldRow("door.left.hand.open", "Rooms", $numRoomsText, keyboard: .numberPad)
                            formDivider()
                            formFieldRow("calendar.badge.clock", "An construit", $yearBuiltText, keyboard: .numberPad)
                        }
                        .padding(.top, 16)

                        // Story
                        Text("POVESTE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4).padding(.top, 20).padding(.bottom, 8)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                            if story.isEmpty {
                                Text("Scrie o poveste despre această proprietate…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.primary.opacity(0.28))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                            }
                            TextEditor(text: $story)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                                .tint(.blue)
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                                .frame(minHeight: 100)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }

                        // Renovations
                        HStack {
                            Text("RENOVĂRI")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.35))
                            Spacer()
                            Button { withAnimation { showRenovationForm.toggle() } } label: {
                                Image(systemName: showRenovationForm ? "minus.circle.fill" : "plus.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 4).padding(.top, 20)

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
                                        Button {
                                            renovations.removeAll { $0.id == r.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color.primary.opacity(0.3))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    if r.id != renovations.last?.id {
                                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 32)
                                    }
                                }
                            }
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                            .padding(.top, 6)
                        }

                        if showRenovationForm {
                            VStack(spacing: 8) {
                                formFieldGroup {
                                    formFieldRow("wrench.fill", "Titlu renovare", $newRenTitle)
                                    formDivider()
                                    formFieldRow("calendar", "Anul start", $newRenFrom, keyboard: .numberPad)
                                    formDivider()
                                    formFieldRow("calendar", "Anul final (opțional)", $newRenTo, keyboard: .numberPad)
                                }
                                Button {
                                    guard !newRenTitle.isEmpty, let from = Int(newRenFrom) else { return }
                                    renovations.append(Renovation(
                                        yearFrom: from,
                                        yearTo: Int(newRenTo),
                                        title: newRenTitle
                                    ))
                                    newRenTitle = ""; newRenFrom = ""; newRenTo = ""
                                    showRenovationForm = false
                                } label: {
                                    Text("Adaugă renovare")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(newRenTitle.isEmpty || newRenFrom.isEmpty ? Color.primary.opacity(0.3) : .blue)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.primary.opacity(0.05),
                                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(newRenTitle.isEmpty || newRenFrom.isEmpty)
                            }
                            .padding(.top, 6)
                        }

                        // Owners
                        HStack {
                            Text("PROPRIETARI")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.35))
                            Spacer()
                            Button { withAnimation { showOwnerForm.toggle() } } label: {
                                Image(systemName: showOwnerForm ? "minus.circle.fill" : "plus.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 4).padding(.top, 20)

                        if !owners.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(owners) { o in
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.primary.opacity(0.4))
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(o.name).font(.system(size: 14, weight: .medium))
                                            Text(o.yearRange).font(.system(size: 12)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button {
                                            owners.removeAll { $0.id == o.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(Color.primary.opacity(0.3))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    if o.id != owners.last?.id {
                                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 40)
                                    }
                                }
                            }
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                            .padding(.top, 6)
                        }

                        if showOwnerForm {
                            VStack(spacing: 8) {
                                formFieldGroup {
                                    formFieldRow("person.fill", "Nume proprietar", $newOwnerName)
                                    formDivider()
                                    formFieldRow("calendar", "Anul start", $newOwnerFrom, keyboard: .numberPad)
                                    formDivider()
                                    formFieldRow("calendar", "Anul final (opțional)", $newOwnerTo, keyboard: .numberPad)
                                }
                                Button {
                                    guard !newOwnerName.isEmpty, let from = Int(newOwnerFrom) else { return }
                                    owners.append(OwnerRecord(
                                        name: newOwnerName,
                                        yearFrom: from,
                                        yearTo: Int(newOwnerTo)
                                    ))
                                    newOwnerName = ""; newOwnerFrom = ""; newOwnerTo = ""
                                    showOwnerForm = false
                                } label: {
                                    Text("Adaugă proprietar")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(newOwnerName.isEmpty || newOwnerFrom.isEmpty ? Color.primary.opacity(0.3) : .blue)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.primary.opacity(0.05),
                                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(newOwnerName.isEmpty || newOwnerFrom.isEmpty)
                            }
                            .padding(.top, 6)
                        }
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

    @ViewBuilder private var mapPickerSection: some View {
        ZStack {
            Map(position: $mapPosition)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onMapCameraChange { ctx in
                    let lat = ctx.camera.centerCoordinate.latitude
                    let lon = ctx.camera.centerCoordinate.longitude
                    latitude = lat
                    longitude = lon
                    latText = String(format: "%.6f", lat)
                    lonText = String(format: "%.6f", lon)
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

        // Manual coordinate input
        HStack(spacing: 8) {
            formCoordField("Latitudine", text: $latText, placeholder: "ex: 44.426800")
            formCoordField("Longitudine", text: $lonText, placeholder: "ex: 26.102500")
            Button {
                applyManualCoords()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private func applyManualCoords() {
        guard let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
              let lon = Double(lonText.replacingOccurrences(of: ",", with: ".")) else { return }
        latitude = lat
        longitude = lon
        mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))
        if !showMap { showMap = true }
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
                if let pc = placemark.postalCode, !pc.isEmpty { postalCode = pc }
                let lat = placemark.coordinate.latitude
                let lon = placemark.coordinate.longitude
                latitude = lat
                longitude = lon
                latText = String(format: "%.6f", lat)
                lonText = String(format: "%.6f", lon)
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
            if let pc = placemark.postalCode, !pc.isEmpty { postalCode = pc }
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

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = property
        updated.name = name
        updated.addressLine1 = addressLine1
        updated.city = city
        updated.country = country
        updated.propertyType = propertyType
        updated.postalCode = postalCode.isEmpty ? nil : postalCode
        updated.sizeSqm = Double(sizeSqmText)
        updated.numRooms = Int(numRoomsText)
        updated.latitude = latitude
        updated.longitude = longitude
        updated.yearBuilt = Int(yearBuiltText)
        updated.story = story.isEmpty ? nil : story
        updated.renovations = renovations
        updated.owners = owners
        await onSave(updated)
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - Shared form helpers

private func formFieldGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
}

private func formFieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
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

private func formDivider() -> some View {
    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
}

private func formCoordField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.4))
        TextField(placeholder, text: text)
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(.primary)
            .tint(.blue)
            .keyboardType(.decimalPad)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .frame(maxWidth: .infinity)
}

// MARK: - Add sheet

private struct AddPropertySheet: View {
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
                        formFieldGroup {
                            formFieldRow("house.fill", "Property name", $name)
                        }

                        VStack(spacing: 0) {
                            formFieldGroup {
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
                                formDivider()
                                formFieldRow("building.2.fill", "City", $city)
                                formDivider()
                                formFieldRow("envelope.fill", "Cod poștal", $postalCode, keyboard: .numbersAndPunctuation)
                                formDivider()
                                formFieldRow("globe.europe.africa.fill", "Country", $country)
                            }

                            if showSuggestions && !completer.suggestions.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(completer.suggestions.prefix(4), id: \.title) { s in
                                        Button { applySuggestion(s) } label: {
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

                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showMap.toggle() }
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
                                        .foregroundStyle(.green).font(.system(size: 14))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain).padding(.top, 12)

                        if showMap { mapPickerSection.padding(.top, 8) }

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

                        formFieldGroup {
                            formFieldRow("ruler.fill", "Area (m²)", $sizeSqmText, keyboard: .decimalPad)
                            formDivider()
                            formFieldRow("door.left.hand.open", "Rooms", $numRoomsText, keyboard: .numberPad)
                        }
                        .padding(.top, 16)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
                }
                .onTapGesture {
                    if showSuggestions { showSuggestions = false }
                    addressFocused = false
                }
            }
            .navigationTitle("Add Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving {
                            ProgressView().tint(.blue)
                        } else {
                            Text("Add")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(name.isEmpty || addressLine1.isEmpty ? Color.primary.opacity(0.3) : Color.blue)
                        }
                    }
                    .disabled(name.isEmpty || addressLine1.isEmpty || isSaving)
                }
            }
        }
    }

    private var mapPickerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Map(position: $mapPosition)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onMapCameraChange { ctx in
                        let lat = ctx.camera.centerCoordinate.latitude
                        let lon = ctx.camera.centerCoordinate.longitude
                        latitude = lat; longitude = lon
                        latText = String(format: "%.6f", lat)
                        lonText = String(format: "%.6f", lon)
                    }
                VStack(spacing: 0) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 7)).foregroundStyle(.red)
                        .rotationEffect(.degrees(180)).offset(y: -3)
                    Spacer()
                }
                .padding(.top, 46)
                VStack {
                    Spacer()
                    HStack {
                        Button { Task { await reverseGeocode() } } label: {
                            Label("Aplică adresa", systemImage: "arrow.up.left.square.fill")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(.blue, in: Capsule())
                        }
                        .buttonStyle(.plain).padding(.leading, 10).padding(.bottom, 10)
                        Spacer()
                        Button { Task { await useCurrentLocation() } } label: {
                            ZStack {
                                Circle().fill(.ultraThinMaterial).frame(width: 36, height: 36)
                                if isLocating {
                                    ProgressView().tint(.blue).scaleEffect(0.7)
                                } else {
                                    Image(systemName: "location.fill").font(.system(size: 14)).foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain).padding(.trailing, 10).padding(.bottom, 10)
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8))

            HStack(spacing: 8) {
                formCoordField("Latitudine", text: $latText, placeholder: "ex: 44.426800")
                formCoordField("Longitudine", text: $lonText, placeholder: "ex: 26.102500")
                Button { applyManualCoords() } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 28)).foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func applySuggestion(_ suggestion: MKLocalSearchCompletion) {
        showSuggestions = false; addressFocused = false
        let req = MKLocalSearch.Request(completion: suggestion)
        Task {
            if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
                let p = item.placemark
                if let t = p.thoroughfare {
                    addressLine1 = t + (p.subThoroughfare.map { " " + $0 } ?? "")
                }
                city = p.locality ?? p.administrativeArea ?? city
                country = p.countryCode ?? country
                if let pc = p.postalCode, !pc.isEmpty { postalCode = pc }
                let lat = p.coordinate.latitude; let lon = p.coordinate.longitude
                latitude = lat; longitude = lon
                latText = String(format: "%.6f", lat)
                lonText = String(format: "%.6f", lon)
                mapPosition = .region(MKCoordinateRegion(
                    center: p.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))
                if !showMap { showMap = true }
            }
        }
    }

    private func reverseGeocode() async {
        guard let lat = latitude, let lon = longitude else { return }
        if let p = try? await CLGeocoder()
            .reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)).first {
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
            mapPosition = .region(MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
            if !showMap { showMap = true }
            await reverseGeocode()
        }
    }

    private func applyManualCoords() {
        guard let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
              let lon = Double(lonText.replacingOccurrences(of: ",", with: ".")) else { return }
        latitude = lat; longitude = lon
        mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))
        if !showMap { showMap = true }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        await propertyService.create(
            name: name,
            addressLine1: addressLine1,
            city: city,
            country: country,
            propertyType: propertyType,
            postalCode: postalCode.isEmpty ? nil : postalCode,
            sizeSqm: Double(sizeSqmText),
            numRooms: Int(numRoomsText),
            latitude: latitude,
            longitude: longitude
        )
        if propertyService.error == nil {
            HapticFeedback.success()
            dismiss()
        }
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
