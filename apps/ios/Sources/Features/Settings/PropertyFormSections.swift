import SwiftUI
import PhotosUI
import MapKit
import CoreLocation

// MARK: - Property form sections (FormKit)
//
// The grouped body shared by AddPropertySheet and EditPropertySheet:
//   Identitate  — cover photo, name, type chips
//   Adresă      — autocomplete search, manual fields, current location,
//                 live map pin preview
//   Detalii     — contextual per type (only columns that exist)
//   Achiziție & valoare — optional, create only (property_value_entries)

struct PropertyFormContent: View {
    @Bindable var draft: PropertyFormDraft
    var showsValueSection: Bool

    var body: some View {
        VStack(spacing: 16) {
            PropertyIdentitySection(draft: draft)
            PropertyAddressSection(draft: draft)
            PropertyDetailsSection(draft: draft)
            if showsValueSection {
                PropertyValueSection(draft: draft)
            }
        }
    }
}

// MARK: - Identitate

struct PropertyIdentitySection: View {
    @Bindable var draft: PropertyFormDraft

    var body: some View {
        FormGroup(title: "prop_form_identity") {
            PropertyCoverPicker(draft: draft)
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            FormDivider()
            FormRow(icon: "house.fill", tint: .accentColor) {
                TextField("prop_form_name", text: $draft.name)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .textInputAutocapitalization(.words)
            }
            FormDivider()
            PropertyTypeChips(selection: $draft.propertyType)
        }
    }
}

// MARK: Cover photo (the property page's hero is set at birth, not later)

struct PropertyCoverPicker: View {
    @Bindable var draft: PropertyFormDraft

    @State private var showMenu = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickerItem: PhotosPickerItem?

    private var hasImage: Bool {
        draft.coverImage != nil || (draft.existingPhotoUrl != nil && !draft.removeExistingPhoto)
    }

    /// Typed as LocalizedStringKey up front — a ternary of string literals
    /// resolves to `String` and would silently skip the catalog.
    private var actionKey: LocalizedStringKey {
        hasImage ? "prop_form_cover_change" : "prop_form_cover_add"
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            showMenu = true
        } label: {
            tile.contentShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(actionKey))
        .confirmationDialog(Text("prop_form_cover_title"), isPresented: $showMenu,
                            titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Text("prop_form_cover_camera") }
            }
            Button { showLibrary = true } label: { Text("prop_form_cover_library") }
            if hasImage {
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.2)) {
                        draft.coverImage = nil
                        draft.removeExistingPhoto = true
                    }
                } label: { Text("prop_form_cover_remove") }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraCapture { image in
                withAnimation(.snappy(duration: 0.2)) {
                    draft.coverImage = image
                    draft.removeExistingPhoto = false
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        withAnimation(.snappy(duration: 0.2)) {
                            draft.coverImage = image
                            draft.removeExistingPhoto = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tile: some View {
        if hasImage {
            coverImageView
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                            .font(AppFont.scaled(11, weight: .semibold))
                        Text("prop_form_cover_change")
                            .font(AppFont.scaled(12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(AppSpacing.sm)
                }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(AppFont.scaled(26, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("prop_form_cover_add")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            .frame(height: 108)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.03),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
    }

    @ViewBuilder
    private var coverImageView: some View {
        if let image = draft.coverImage {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let url = draft.existingPhotoUrl {
            StorageImage(source: url, targetSize: 600) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    Color.primary.opacity(AppOpacity.subtleFill)
                }
            }
        }
    }
}

// MARK: Type chips

struct PropertyTypeChips: View {
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PropertyKind.allCases, id: \.rawValue) { kind in
                    chip(kind)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .accessibilityLabel(Text("prop_form_type"))
    }

    private func chip(_ kind: PropertyKind) -> some View {
        let selected = selection == kind.rawValue
        return Button {
            guard !selected else { return }
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.25)) { selection = kind.rawValue }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(AppOpacity.mediumText))
                Text(kind.labelKey)
                    .font(AppFont.scaled(13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : Color.primary.opacity(AppOpacity.emphasis))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm)
            .glassFilterCapsule(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: kind.localizedName))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Adresă inteligentă

struct PropertyAddressSection: View {
    @Bindable var draft: PropertyFormDraft

    @State private var completer = AddressCompleter()
    @State private var locationFix = CurrentLocationFix()
    @State private var searchText = ""
    @State private var showSuggestions = false
    @State private var isResolvingPick = false
    @State private var isReverseGeocoding = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormGroup(title: "prop_form_address") {
                searchRow
                suggestionRows
                FormDivider()
                manualRows
                FormDivider()
                currentLocationRow
                mapPreview
            }
            if !draft.hasLocation {
                Text("prop_form_address_hint")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .padding(.leading, AppSpacing.xxs)
            }
        }
        .onAppear {
            locationFix.readStatus()
            if !draft.country.isEmpty { completer.setCountry(draft.country) }
        }
        .onChange(of: draft.country) { _, code in completer.setCountry(code) }
    }

    // MARK: Search + suggestions

    private var searchRow: some View {
        FormRow(icon: "magnifyingglass", tint: .accentColor) {
            TextField("prop_form_address_search", text: $searchText)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .focused($searchFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, text in
                    completer.query(text)
                    showSuggestions = !text.isEmpty
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    completer.suggestions = []
                    showSuggestions = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("prop_form_clear"))
            }
        }
    }

    @ViewBuilder
    private var suggestionRows: some View {
        if showSuggestions && !completer.suggestions.isEmpty {
            let items = Array(completer.suggestions.prefix(5))
            ForEach(Array(items.enumerated()), id: \.offset) { _, suggestion in
                FormDivider()
                Button { pick(suggestion) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .font(AppFont.scaled(16))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: suggestion.title)
                                .font(AppFont.footnote)
                                .foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(verbatim: suggestion.subtitle)
                                    .font(AppFont.scaled(12))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(isResolvingPick)
            }
        }
    }

    /// A tapped completion fills the whole address immediately, then refines
    /// street/city/postal/country and coordinates via a precise placemark
    /// lookup — the same two-phase fill the app's other pickers use.
    private func pick(_ suggestion: MKLocalSearchCompletion) {
        HapticFeedback.selection()
        isResolvingPick = true
        showSuggestions = false
        searchFocused = false
        searchText = ""
        completer.suggestions = []

        // Immediate fill so the form reflects the choice right away.
        draft.addressLine1 = suggestion.title
        let ignore: Set<String> = ["românia", "romania", "belgië", "belgique", "belgium", "belgia"]
        let parts = suggestion.subtitle
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !ignore.contains($0.lowercased()) }
        if let firstCity = parts.first { draft.city = firstCity }

        let request = MKLocalSearch.Request(completion: suggestion)
        Task {
            defer { isResolvingPick = false }
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return }
            let placemark = item.placemark
            if let street = placemark.thoroughfare {
                draft.addressLine1 = street + (placemark.subThoroughfare.map { " " + $0 } ?? "")
            }
            if let locality = placemark.locality {
                draft.city = locality
            } else if let area = placemark.administrativeArea {
                draft.city = area
            }
            if let postal = placemark.postalCode, !postal.isEmpty { draft.postalCode = postal }
            if let code = placemark.isoCountryCode { draft.country = code }
            draft.setCoordinate(placemark.coordinate, recenter: true)
        }
    }

    // MARK: Manual fields (always available for correction)

    @ViewBuilder
    private var manualRows: some View {
        FormRow(icon: "mappin.and.ellipse", tint: .accentColor) {
            TextField("prop_form_street", text: $draft.addressLine1)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .textInputAutocapitalization(.words)
        }
        FormDivider()
        FormRow(icon: "building.2.fill", tint: .accentColor) {
            TextField("prop_form_city", text: $draft.city)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .textInputAutocapitalization(.words)
        }
        FormDivider()
        FormRow(icon: "envelope.fill", tint: .accentColor) {
            TextField("prop_form_postal", text: $draft.postalCode)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(.numbersAndPunctuation)
        }
        FormDivider()
        FormRow(icon: "globe.europe.africa.fill", tint: .accentColor) {
            TextField("prop_form_country", text: $draft.country)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
    }

    // MARK: Current location (honest permission flow)

    private var currentLocationRow: some View {
        Button {
            useCurrentLocation()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: locationFix.isDenied ? "location.slash.fill" : "location.circle.fill")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(locationFix.isDenied
                        ? Color.primary.opacity(AppOpacity.mediumText) : Color.brandSkyBlue)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    // Bound to LocalizedStringKey first — a ternary of string
                    // literals is a `String` and would skip the catalog.
                    let titleKey: LocalizedStringKey = locationFix.isDenied
                        ? "prop_form_location_off" : "prop_form_use_location"
                    Text(titleKey)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    if locationFix.isDenied {
                        Text("prop_form_open_settings")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.secondary)
                    } else if locationFix.isLocating || isReverseGeocoding {
                        Text("prop_form_locating")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if locationFix.isLocating || isReverseGeocoding {
                    ProgressView().controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.base)
        }
        .buttonStyle(.plain)
        .disabled(locationFix.isLocating || isReverseGeocoding)
    }

    private func useCurrentLocation() {
        HapticFeedback.impact(.light)
        if locationFix.isDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        locationFix.locate { location in
            guard let location else {
                if !locationFix.isDenied { HapticFeedback.error() }
                return
            }
            draft.setCoordinate(location.coordinate, recenter: true)
            Task { await fillAddress(from: location.coordinate) }
        }
    }

    // MARK: Live map pin preview

    private var mapPreview: some View {
        VStack(spacing: 8) {
            MapReader { proxy in
                Map(position: $draft.mapPosition) {
                    if let coordinate = draft.coordinate {
                        Annotation("", coordinate: coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(AppFont.scaled(28, weight: .semibold))
                                .foregroundStyle(.white, Color.brandDanger)
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                )
                .overlay(alignment: .bottom) {
                    if draft.coordinate == nil {
                        Text("prop_form_map_hint")
                            .font(AppFont.scaled(12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(.bottom, AppSpacing.sm)
                            .allowsHitTesting(false)
                    }
                }
                .onTapGesture { point in
                    guard let coordinate = proxy.convert(point, from: .local) else { return }
                    HapticFeedback.selection()
                    withAnimation(.snappy(duration: 0.2)) {
                        draft.setCoordinate(coordinate, recenter: false)
                    }
                }
                .accessibilityLabel(Text("prop_form_map_hint"))
            }

            if let coordinate = draft.coordinate {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.brandDanger)
                    Text(verbatim: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        .font(AppFont.scaled(12).monospacedDigit())
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer(minLength: 0)
                    Button {
                        HapticFeedback.impact(.light)
                        Task { await fillAddress(from: coordinate) }
                    } label: {
                        HStack(spacing: 4) {
                            if isReverseGeocoding {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.uturn.up")
                                    .font(AppFont.scaled(10, weight: .semibold))
                            }
                            Text("prop_form_apply_address")
                                .font(AppFont.scaled(12, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(isReverseGeocoding)
                }
                .padding(.horizontal, AppSpacing.xs)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.md)
    }

    /// Reverse-geocodes the pin into the manual fields — only overwriting a
    /// field when Apple actually knows the answer.
    private func fillAddress(from coordinate: CLLocationCoordinate2D) async {
        isReverseGeocoding = true
        defer { isReverseGeocoding = false }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        if let street = placemark.thoroughfare {
            draft.addressLine1 = street + (placemark.subThoroughfare.map { " " + $0 } ?? "")
        }
        if let locality = placemark.locality { draft.city = locality }
        if let postal = placemark.postalCode, !postal.isEmpty { draft.postalCode = postal }
        if let code = placemark.isoCountryCode { draft.country = code }
    }
}

// MARK: - Detalii (contextual per type)

struct PropertyDetailsSection: View {
    @Bindable var draft: PropertyFormDraft

    private var kind: PropertyKind { draft.kind ?? .other }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormGroup(title: "prop_form_details") {
                FormRow(icon: "ruler.fill", tint: .accentColor) {
                    TextField(kind.areaLabelKey, text: $draft.areaText)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        .keyboardType(.decimalPad)
                }
                if kind.showsRooms {
                    FormDivider()
                    FormRow(icon: "door.left.hand.open", tint: .accentColor) {
                        TextField("prop_form_rooms", text: $draft.roomsText)
                            .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                            .keyboardType(.numberPad)
                    }
                }
                if kind.showsYearBuilt {
                    FormDivider()
                    FormRow(icon: "calendar.badge.clock", tint: .accentColor) {
                        TextField("prop_form_year_built", text: $draft.yearBuiltText)
                            .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                            .keyboardType(.numberPad)
                    }
                }
            }
            if !draft.yearBuiltIsValid {
                Label {
                    Text("prop_form_year_invalid")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.brandWarning)
                .padding(.leading, AppSpacing.xxs)
            }
        }
        .animation(.smooth(duration: 0.25), value: draft.propertyType)
        .animation(.smooth(duration: 0.2), value: draft.yearBuiltIsValid)
    }
}

// MARK: - Achiziție & valoare (opțional, create only)
//
// Both amounts become property_value_entries rows — the same table the
// "Valoarea proprietății" page reads — so the value history starts on day one
// without inventing any new storage.

struct PropertyValueSection: View {
    @Bindable var draft: PropertyFormDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormGroup(title: "prop_form_value_section") {
                FormRow(icon: "banknote.fill", tint: .accentColor) {
                    TextField("prop_form_purchase_price", text: $draft.purchasePriceText)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        .keyboardType(.decimalPad)
                    Picker("prop_form_currency", selection: $draft.currency) {
                        ForEach(CurrencyService.supported, id: \.code) { entry in
                            Text(verbatim: entry.code).tag(entry.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.accentColor)
                    .labelsHidden()
                }
                if draft.purchasePrice != nil {
                    FormDivider()
                    DatePicker("prop_form_purchase_date",
                               selection: $draft.purchaseDate,
                               in: ...Date(),
                               displayedComponents: .date)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.md)
                }
                FormDivider()
                FormRow(icon: "chart.line.uptrend.xyaxis", tint: .accentColor) {
                    TextField("prop_form_estimated_value", text: $draft.estimatedValueText)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        .keyboardType(.decimalPad)
                    Text(verbatim: draft.currency)
                        .font(AppFont.scaled(13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
            }
            Text("prop_form_value_footer")
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .padding(.leading, AppSpacing.xxs)
        }
        .animation(.smooth(duration: 0.25), value: draft.purchasePrice != nil)
    }
}
