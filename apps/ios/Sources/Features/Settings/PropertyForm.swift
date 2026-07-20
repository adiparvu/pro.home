import SwiftUI
import Observation
import MapKit
import CoreLocation

// MARK: - Property form domain
//
// One draft object powers both AddPropertySheet and EditPropertySheet, so the
// create and edit experiences can never drift apart. Persistence stays honest:
// the draft only carries fields with a real column in `properties`
// (name, address parts, country, lat/lon, type, size_sqm, num_rooms,
// year_built, photo_url, story, renovations, owners) plus the optional
// purchase/estimate amounts that become `property_value_entries` rows.

// MARK: Property kind (stored raw values are backward compatible)

/// The property types the form offers. Raw values are the exact strings the
/// `properties.property_type` column already stores — `apartment`, `house`,
/// `villa`, `studio`, `commercial`, `other` predate this form and must keep
/// decoding; `cabin` and `land` are additive. A row with an unknown raw value
/// simply renders no selected chip and keeps its stored string on save.
enum PropertyKind: String, CaseIterable {
    case apartment, house, villa, studio, cabin, land, commercial, other

    var labelKey: LocalizedStringKey {
        switch self {
        case .apartment:  "prop_type_apartment"
        case .house:      "prop_type_house"
        case .villa:      "prop_type_villa"
        case .studio:     "prop_type_studio"
        case .cabin:      "prop_type_cabin"
        case .land:       "prop_type_land"
        case .commercial: "prop_type_commercial"
        case .other:      "prop_type_other"
        }
    }

    var localizedName: String {
        switch self {
        case .apartment:  String(localized: "prop_type_apartment")
        case .house:      String(localized: "prop_type_house")
        case .villa:      String(localized: "prop_type_villa")
        case .studio:     String(localized: "prop_type_studio")
        case .cabin:      String(localized: "prop_type_cabin")
        case .land:       String(localized: "prop_type_land")
        case .commercial: String(localized: "prop_type_commercial")
        case .other:      String(localized: "prop_type_other")
        }
    }

    var icon: String {
        switch self {
        case .apartment:  "building.2.fill"
        case .house:      "house.fill"
        case .villa:      "house.and.flag.fill"
        case .studio:     "bed.double.fill"
        case .cabin:      "house.lodge.fill"
        case .land:       "map.fill"
        case .commercial: "storefront.fill"
        case .other:      "ellipsis.circle.fill"
        }
    }

    // Contextual details — only fields that make sense for the type, and only
    // fields with a real column. Land is just a surface; a commercial space
    // has an area and a build year but "rooms" would be noise.
    var showsRooms: Bool { self != .land && self != .commercial }
    var showsYearBuilt: Bool { self != .land }
    var areaLabelKey: LocalizedStringKey {
        self == .land ? "prop_form_land_area" : "prop_form_area"
    }
}

// MARK: Draft (all form state, shared by create + edit)

@MainActor
@Observable
final class PropertyFormDraft {
    // Identity
    var name = ""
    /// Raw stored value — kept as a String (not PropertyKind) so an existing
    /// row with an unrecognised type round-trips unchanged unless the user
    /// deliberately picks a chip.
    var propertyType = PropertyKind.apartment.rawValue
    /// A freshly picked cover image; uploads through
    /// `PropertyService.uploadPhoto` after the row exists.
    var coverImage: UIImage?
    /// Edit only: the property's current cover, shown until replaced/removed.
    var existingPhotoUrl: String?
    var removeExistingPhoto = false

    // Address
    var addressLine1 = ""
    var city = ""
    var postalCode = ""
    var country = "RO"
    var latitude: Double?
    var longitude: Double?
    // Explicit type: covariant `Self` can't appear in a class's stored
    // property initializer.
    var mapPosition: MapCameraPosition = .region(PropertyFormDraft.defaultRegion)

    // Details (each backed by a real column)
    var areaText = ""
    var roomsText = ""
    var yearBuiltText = ""

    // Purchase & value (create only → property_value_entries rows)
    var purchasePriceText = ""
    var purchaseDate = Date()
    var estimatedValueText = ""
    var currency = "EUR"

    // Rich profile (edit only, existing columns)
    var story = ""
    var renovations: [Renovation] = []
    var owners: [OwnerRecord] = []

    init() {}

    init(property: PropertyModel) {
        name = property.name
        propertyType = property.propertyType
        existingPhotoUrl = property.photoUrl
        addressLine1 = property.addressLine1
        city = property.city
        postalCode = property.postalCode ?? ""
        country = property.country
        latitude = property.latitude
        longitude = property.longitude
        areaText = property.sizeSqm.map { $0.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", $0) : String($0) } ?? ""
        roomsText = property.numRooms.map(String.init) ?? ""
        yearBuiltText = property.yearBuilt.map(String.init) ?? ""
        story = property.story ?? ""
        renovations = property.renovations ?? []
        owners = property.owners ?? []
        if let lat = property.latitude, let lon = property.longitude {
            mapPosition = .region(Self.region(around: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        }
    }

    // MARK: Derived

    var kind: PropertyKind? { PropertyKind(rawValue: propertyType) }
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedAddress: String { addressLine1.trimmingCharacters(in: .whitespacesAndNewlines) }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var area: Double? { Self.number(areaText) }
    var rooms: Int? { Int(roomsText.trimmingCharacters(in: .whitespaces)) }
    var yearBuilt: Int? { Int(yearBuiltText.trimmingCharacters(in: .whitespaces)) }
    var purchasePrice: Double? { Self.number(purchasePriceText) }
    var estimatedValue: Double? { Self.number(estimatedValueText) }

    /// Empty is fine (the field is optional); a typed year must be plausible.
    var yearBuiltIsValid: Bool {
        let text = yearBuiltText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        guard let year = Int(text) else { return false }
        return (1400...Calendar.current.component(.year, from: Date())).contains(year)
    }

    /// A property needs a name and a way to find it — either a postal address
    /// or a pin on the map.
    var hasLocation: Bool { !trimmedAddress.isEmpty || coordinate != nil }
    var canSave: Bool { !trimmedName.isEmpty && hasLocation && yearBuiltIsValid }

    // MARK: Mutations

    /// Sets the pin. Recentring is for programmatic fills (autocomplete,
    /// current location); a map tap keeps the camera exactly where the user
    /// put it.
    func setCoordinate(_ coordinate: CLLocationCoordinate2D, recenter: Bool) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        if recenter {
            withAnimation(.smooth(duration: 0.3)) {
                mapPosition = .region(Self.region(around: coordinate))
            }
        }
    }

    /// Applies the draft to an existing model (edit flow). The cover image
    /// itself uploads separately via `PropertyService.uploadPhoto`.
    func applied(to property: PropertyModel) -> PropertyModel {
        var updated = property
        updated.name = trimmedName
        updated.propertyType = propertyType
        updated.addressLine1 = trimmedAddress
        updated.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.postalCode = postalCode.isEmpty ? nil : postalCode
        updated.country = country
        updated.latitude = latitude
        updated.longitude = longitude
        updated.sizeSqm = area
        // Values persist as drafted even when the row is hidden for the
        // current type — switching type must never silently destroy data.
        updated.numRooms = rooms
        updated.yearBuilt = yearBuilt
        updated.story = story.isEmpty ? nil : story
        updated.renovations = renovations
        updated.owners = owners
        if removeExistingPhoto { updated.photoUrl = nil }
        return updated
    }

    // MARK: Helpers

    /// Locale-tolerant decimal parsing ("112,5" and "112.5" both work).
    static func number(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    static func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate,
                           span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
    }

    /// România overview — the honest default before any pin exists.
    static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.9, longitude: 24.9),
        span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 8))
}

// MARK: - Address autocomplete engine

@MainActor
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    var suggestions: [MKLocalSearchCompletion] = []
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

    func query(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = trimmed
        }
    }

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

// MARK: - Honest one-shot current location
//
// Same contract as the task location sheet (TaskNearbyPlacesModel): the form
// never prompts on its own — the system dialog appears only from the user's
// own "Folosește locația curentă" tap while status is .notDetermined, and a
// deny flips the row into an "open Settings" state instead of failing
// silently. nil in the callback always means "no position", never a fake.

@MainActor
@Observable
final class CurrentLocationFix: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isLocating = false

    @ObservationIgnored private lazy var manager: CLLocationManager = {
        let m = CLLocationManager()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return m
    }()
    @ObservationIgnored private var onFix: ((CLLocation?) -> Void)?

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// Reads the status without ever prompting (call on appear).
    func readStatus() {
        authorization = manager.authorizationStatus
    }

    /// The user's tap. `.notDetermined` shows the system dialog — the one
    /// moment a prompt is exactly what they asked for.
    func locate(_ completion: @escaping (CLLocation?) -> Void) {
        onFix = completion
        isLocating = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            resolve(with: nil)
        }
    }

    private func requestFix() {
        manager.requestLocation()
    }

    private func resolve(with location: CLLocation?) {
        isLocating = false
        guard let pending = onFix else { return }
        onFix = nil
        pending(location)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            guard self.onFix != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.requestFix()
            case .denied, .restricted:
                self.resolve(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor [weak self] in self?.resolve(with: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.resolve(with: nil) }
    }
}
