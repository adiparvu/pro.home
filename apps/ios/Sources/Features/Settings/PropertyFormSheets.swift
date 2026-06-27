import SwiftUI
import MapKit
import CoreLocation

// MARK: - Address Autocomplete

@MainActor
final class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    @Published var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    // Bounding boxes for supported countries
    private static let regions: [String: MKCoordinateRegion] = [
        "RO": MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 45.9, longitude: 24.9),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 12)
        ),
        "BE": MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.5, longitude: 4.5),
            span: MKCoordinateSpan(latitudeDelta: 3.5, longitudeDelta: 5)
        )
    ]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        // Default: România
        if let ro = Self.regions["RO"] { completer.region = ro }
    }

    func setCountry(_ code: String) {
        if let region = Self.regions[code.uppercased()] {
            completer.region = region
        }
    }

    func query(_ text: String) { completer.queryFragment = text }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            // Deduplicate by "title|subtitle" — MKLocalSearchCompleter can return
            // the same address from multiple data sources
            var seen = Set<String>()
            self.suggestions = results.filter {
                seen.insert("\($0.title)|\($0.subtitle)").inserted
            }
        }
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

// MARK: - Address Autocomplete Field (reusable)
//
// One self-contained address block: Street + City + Postal + Country with a
// live suggestion dropdown. Picking a suggestion fills every field reliably:
//   • The street is filled immediately from the chosen completion (so the field
//     never just "stays as typed"), then refined via MKLocalSearch for the
//     precise street/city/postal/coordinates.
//   • While applying a pick we suppress the completer (isApplying) so the
//     programmatic field change does NOT re-open the dropdown.

struct AddressAutocompleteField: View {
    @Binding var addressLine1: String
    @Binding var city: String
    @Binding var postalCode: String
    @Binding var country: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    var onPicked: () -> Void = {}

    @StateObject private var completer = AddressCompleter()
    @State private var showSuggestions = false
    @State private var isApplying = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            formFieldGroup {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.fill")
                        .font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                    TextField("Street and number", text: $addressLine1)
                        .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: addressLine1) { _, val in
                            guard !isApplying else { return }
                            completer.query(val)
                            showSuggestions = !val.isEmpty
                        }
                    if !addressLine1.isEmpty {
                        Button {
                            addressLine1 = ""; completer.suggestions = []; showSuggestions = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.3))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                formDivider()
                formFieldRow("building.2.fill", "City", $city)
                formDivider()
                formFieldRow("envelope.fill", "Postal code", $postalCode, keyboard: .numbersAndPunctuation)
                formDivider()
                formFieldRow("globe.europe.africa.fill", "Country", $country)
                    .onChange(of: country) { _, code in completer.setCountry(code) }
            }
            if showSuggestions && !completer.suggestions.isEmpty {
                suggestionList
            }
        }
        .onAppear { if !country.isEmpty { completer.setCountry(country) } }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                // Delay hiding so a tap on a suggestion registers first.
                Task { try? await Task.sleep(for: .milliseconds(250)); showSuggestions = false }
            } else if !addressLine1.isEmpty {
                showSuggestions = !completer.suggestions.isEmpty
            }
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            let items = Array(completer.suggestions.prefix(6))
            ForEach(Array(items.enumerated()), id: \.offset) { idx, s in
                Button { pick(s) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 16)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary)
                            if !s.subtitle.isEmpty {
                                Text(s.subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                if idx < items.count - 1 { Divider().padding(.leading, 44) }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .padding(.top, 6)
    }

    private func pick(_ s: MKLocalSearchCompletion) {
        isApplying = true
        showSuggestions = false
        focused = false
        completer.suggestions = []
        HapticFeedback.selection()

        // Immediate fill so the field reflects the choice right away.
        addressLine1 = s.title
        let ignore: Set<String> = ["românia", "romania", "belgië", "belgique", "belgium", "belgia"]
        let parts = s.subtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !ignore.contains($0.lowercased()) }
        if let firstCity = parts.first { city = firstCity }

        // Refine with a precise placemark lookup.
        let req = MKLocalSearch.Request(completion: s)
        Task {
            if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
                let p = item.placemark
                await MainActor.run {
                    if let t = p.thoroughfare {
                        addressLine1 = t + (p.subThoroughfare.map { " " + $0 } ?? "")
                    }
                    if let l = p.locality { city = l }
                    else if let a = p.administrativeArea { city = a }
                    if let pc = p.postalCode, !pc.isEmpty { postalCode = pc }
                    if let cc = p.isoCountryCode { country = cc }
                    latitude = p.coordinate.latitude
                    longitude = p.coordinate.longitude
                }
            }
            // Keep the completer suppressed until programmatic edits settle.
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run {
                isApplying = false
                onPicked()
            }
        }
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

    private let propertyTypes = ["apartment", "house", "villa", "studio", "commercial", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
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
                        .padding(.top, 16)

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
                                        Text(LocalizedStringKey(type.capitalized))
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
                .scrollDismissesKeyboard(.interactively)
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
