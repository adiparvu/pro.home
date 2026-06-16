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
