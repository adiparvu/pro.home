import SwiftUI
import PhotosUI
import MapKit
import Supabase

// MARK: - Task photos (form section + upload)
//
// Photos attach from the task form (IMG_8216): a PhotosPicker row under the
// description, thumbnails in a horizontal strip with per-photo delete.
// Existing URLs (editing) and freshly picked images live side by side; the
// pending images upload on save through the same pipeline as Photo Journal
// (documents bucket, resized JPEG, public URL).

struct TaskPhotoSection: View {
    @Binding var existingUrls: [String]
    @Binding var pendingImages: [UIImage]

    @State private var pickerItems: [PhotosPickerItem] = []
    private let maxPhotos = 6

    private var remaining: Int { max(0, maxPhotos - existingUrls.count - pendingImages.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Text("task_photos_title")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                Spacer()
                if remaining > 0 {
                    PhotosPicker(selection: $pickerItems,
                                 maxSelectionCount: remaining,
                                 matching: .images) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(AppFont.scaled(12, weight: .semibold))
                            Text("task_photos_add")
                                .font(AppFont.scaled(13, weight: .medium))
                        }
                        .foregroundStyle(Color.brandPurple)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 6)
                        // Same Liquid Glass capsule as the form's filter
                        // chips — the brandPurple label carries the accent.
                        .glassFilterCapsule(selected: false)
                    }
                }
            }

            if !existingUrls.isEmpty || !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(existingUrls, id: \.self) { url in
                            thumb {
                                AsyncImage(url: URL(string: url)) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Color.primary.opacity(AppOpacity.subtleFill)
                                    }
                                }
                            } onDelete: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    existingUrls.removeAll { $0 == url }
                                }
                            }
                        }
                        ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, image in
                            thumb {
                                Image(uiImage: image).resizable().scaledToFill()
                            } onDelete: {
                                withAnimation(.snappy(duration: 0.2)) {
                                    if pendingImages.indices.contains(index) {
                                        pendingImages.remove(at: index)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            withAnimation(.snappy(duration: 0.2)) { pendingImages.append(image) }
                        }
                    }
                }
            }
        }
    }

    private func thumb<Content: View>(@ViewBuilder content: () -> Content,
                                      onDelete: @escaping () -> Void) -> some View {
        content()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel(Text("task_photos_remove"))
            }
    }
}

enum TaskPhotoUploader {
    /// Uploads freshly picked photos and returns their public URLs — the same
    /// pipeline Photo Journal uses (documents bucket, resized JPEG).
    static func upload(_ images: [UIImage], propertyId: UUID) async throws -> [String] {
        guard let ownerId = supabase.auth.currentSession?.user.id else { return [] }
        var urls: [String] = []
        for image in images {
            guard let data = image.uploadJPEG(quality: 0.8) else { continue }
            let path = "\(ownerId.uuidString.lowercased())/tasks/\(propertyId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            try await supabase.storage
                .from("documents")
                .upload(path, data: data,
                        options: FileOptions(contentType: "image/jpeg", upsert: false))
            let publicURL = try supabase.storage.from("documents").getPublicURL(path: path)
            urls.append(publicURL.absoluteString)
        }
        return urls
    }
}

// MARK: - Task location (form row + Apple Maps picker)
//
// The place a task happens (IMG_8217): either a real Apple Maps location
// (live search results, name + coordinates) or exactly the text the user
// typed. Coordinates are kept only for real picks, so the detail page can
// open Maps honestly.

struct TaskLocationValue: Equatable {
    var name: String
    var lat: Double?
    var lon: Double?
}

struct TaskLocationSection: View {
    @Binding var location: TaskLocationValue?
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                Text("task_location_title")
                    .font(AppFont.scaled(14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            }

            Button {
                HapticFeedback.impact(.light)
                showPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: location == nil ? "mappin.circle" : "mappin.circle.fill")
                        .font(AppFont.scaled(17))
                        .foregroundStyle(Color.brandPurple)
                        .frame(width: 22)
                    Text(location?.name ?? String(localized: "task_location_add"))
                        .font(AppFont.scaled(15))
                        .foregroundStyle(location == nil ? Color.primary.opacity(AppOpacity.disabled) : .primary)
                        .lineLimit(1)
                    Spacer()
                    if location != nil {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { location = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.primary.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("task_location_clear"))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(0.28))
                    }
                }
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) {
            TaskLocationPickerSheet(location: $location)
        }
    }
}

/// Live Apple Maps completions for the picker (MKLocalSearchCompleter).
@Observable
final class TaskLocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private lazy var completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.delegate = self
        c.resultTypes = [.address, .pointOfInterest]
        return c
    }()

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

struct TaskLocationPickerSheet: View {
    @Binding var location: TaskLocationValue?
    @Environment(\.dismiss) private var dismiss
    // Optional on purpose: the sheet is also presented from the chat event
    // composer — a host without PropertyService simply has no property row,
    // it must never crash the sheet.
    @Environment(PropertyService.self) private var propertyService: PropertyService?

    @State private var model = TaskLocationSearchModel()
    @State private var nearby = TaskNearbyPlacesModel()
    @State private var remembered = TaskLocationMemory.load()
    @State private var query = ""
    @State private var isResolving = false
    @State private var isResolvingProperty = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    propertySection
                    positionSection
                    rememberedSections
                } else {
                    searchContent
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("task_location_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("task_location_search"))
            .onChange(of: query) { _, q in model.update(query: q) }
            // Reads the permission status and, when it already exists, feeds
            // "În apropiere". The system dialog only ever appears from the
            // user's own "Folosește poziția mea" tap.
            .task { nearby.start() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Search (free text + live Apple Maps completions)

    @ViewBuilder
    private var searchContent: some View {
        Button {
            select(TaskLocationValue(name: trimmedQuery, lat: nil, lon: nil))
        } label: {
            Label {
                Text(String(format: String(localized: "task_location_use_text"), trimmedQuery))
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "character.cursor.ibeam")
                    .foregroundStyle(Color.brandPurple)
            }
        }

        ForEach(model.results, id: \.self) { completion in
            Button {
                resolve(completion)
            } label: {
                placeLabel(title: completion.title, subtitle: completion.subtitle,
                           icon: "mappin.circle.fill", tint: Color.brandDanger)
            }
            .disabled(isResolving)
        }
    }

    // MARK: Property location (always offered when a primary property exists)

    /// The primary property's postal address, or nil when no line is set —
    /// the row still shows with stored coordinates, otherwise it hides
    /// entirely (a row that could select nothing would be a dead control).
    private var propertyAddress: String? {
        guard let p = propertyService?.primary else { return nil }
        let joined = [p.addressLine1, p.city, p.country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    @ViewBuilder
    private var propertySection: some View {
        if let property = propertyService?.primary,
           (property.latitude != nil && property.longitude != nil) || propertyAddress != nil {
            Section {
                Button {
                    selectProperty(property)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("locpick_property")
                                .foregroundStyle(.primary)
                            Group {
                                if isResolvingProperty {
                                    Text("locpick_locating")
                                } else {
                                    Text(verbatim: propertySubtitle(for: property))
                                }
                            }
                            .font(AppFont.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "house.circle.fill")
                            .foregroundStyle(Color.brandSuccess)
                    }
                }
                .disabled(isResolvingProperty)
                .overlay(alignment: .trailing) {
                    if isResolvingProperty { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    /// What the row promises to select: the property's name when it has one,
    /// otherwise its address.
    private func propertySubtitle(for property: PropertyModel) -> String {
        let name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let address = propertyAddress {
            return name.isEmpty ? address : "\(name) · \(address)"
        }
        return name
    }

    /// Stored coordinates select instantly; an address-only property geocodes
    /// on tap (spinner in the row). If geocoding fails, the address is still
    /// selected as plain text — the row always does something real.
    private func selectProperty(_ property: PropertyModel) {
        let name = property.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? (propertyAddress ?? "") : name
        if let lat = property.latitude, let lon = property.longitude {
            select(TaskLocationValue(name: displayName, lat: lat, lon: lon))
            return
        }
        guard let address = propertyAddress else { return }
        isResolvingProperty = true
        Task { @MainActor in
            let placemarks = (try? await CLGeocoder().geocodeAddressString(address)) ?? []
            isResolvingProperty = false
            if let coord = placemarks.first?.location?.coordinate {
                select(TaskLocationValue(name: displayName,
                                         lat: coord.latitude, lon: coord.longitude))
            } else {
                select(TaskLocationValue(name: address, lat: nil, lon: nil))
            }
        }
    }

    // MARK: Current position + nearby

    /// Always one honest row: "Folosește poziția mea" prompts/locates on tap;
    /// denied/restricted swaps it for an "open Settings" row. Nearby results
    /// follow underneath once a fix exists.
    private var positionSection: some View {
        Section {
            if nearby.isDenied {
                Button {
                    HapticFeedback.impact(.light)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("locpick_location_off")
                                .foregroundStyle(.primary)
                            Text("locpick_open_settings")
                                .font(AppFont.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "location.slash.fill")
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                }
            } else {
                Button {
                    useMyPosition()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("locpick_my_position")
                                .foregroundStyle(.primary)
                            if nearby.isLocating || isResolving {
                                Text("locpick_locating")
                                    .font(AppFont.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "location.circle.fill")
                            .foregroundStyle(Color.brandSkyBlue)
                    }
                }
                .disabled(nearby.isLocating || isResolving)
                .overlay(alignment: .trailing) {
                    if nearby.isLocating || isResolving { ProgressView().controlSize(.small) }
                }
            }

            ForEach(Array(nearby.places.enumerated()), id: \.offset) { _, item in
                Button {
                    let coord = item.placemark.coordinate
                    select(TaskLocationValue(name: item.name ?? "",
                                             lat: coord.latitude, lon: coord.longitude))
                } label: {
                    placeLabel(title: item.name ?? "",
                               subtitle: item.placemark.title ?? "",
                               icon: "mappin.circle.fill", tint: Color.brandSkyBlue)
                }
            }
        } header: {
            sectionHeader(icon: "location", title: "locpick_nearby")
        }
    }

    /// The tap that may legitimately show the system permission dialog. A
    /// granted fix reverse-geocodes into a readable name ("Str. Aviatorilor
    /// 12, București"), falling back to "Poziția mea"; a deny flips the row
    /// into the Settings state via `nearby.isDenied`.
    private func useMyPosition() {
        HapticFeedback.impact(.light)
        nearby.useMyPosition { fix in
            guard let fix else {
                // Denied → the row already switched to "open Settings".
                // A failed fix while authorized deserves an audible shrug.
                if !nearby.isDenied { HapticFeedback.error() }
                return
            }
            isResolving = true
            Task { @MainActor in
                let name = await Self.reverseGeocodedName(for: fix.coordinate)
                    ?? String(localized: "locpick_my_position_fallback")
                isResolving = false
                select(TaskLocationValue(name: name,
                                         lat: fix.coordinate.latitude,
                                         lon: fix.coordinate.longitude))
            }
        }
    }

    /// Best-effort "street number, locality" name for a coordinate — the same
    /// shape the chat share sheet renders for dropped pins.
    private static func reverseGeocodedName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let street = mark.thoroughfare.map { t in
            mark.subThoroughfare.map { "\(t) \($0)" } ?? t
        }
        let parts = [street ?? mark.name, mark.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Remembered picks (Favorite / Frecvente / Recente)

    @ViewBuilder
    private var rememberedSections: some View {
        let split = TaskLocationMemory.sections(of: remembered)
        if !split.favorites.isEmpty {
            Section {
                ForEach(split.favorites) { rememberedRow($0) }
            } header: {
                sectionHeader(icon: "star.fill", title: "locpick_favorites")
            }
        }
        if !split.frequent.isEmpty {
            Section {
                ForEach(split.frequent) { rememberedRow($0) }
            } header: {
                sectionHeader(icon: "flame", title: "locpick_frequent")
            }
        }
        if !split.recent.isEmpty {
            Section {
                ForEach(split.recent) { rememberedRow($0) }
            } header: {
                sectionHeader(icon: "clock", title: "locpick_recent")
            }
        }
    }

    private func rememberedRow(_ item: RememberedTaskLocation) -> some View {
        Button {
            select(item.value)
        } label: {
            placeLabel(title: item.name, subtitle: "",
                       icon: item.isFavorite ? "star.circle.fill" : "mappin.circle.fill",
                       tint: item.isFavorite ? Color.brandWarning : Color.brandPurple)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    remembered = TaskLocationMemory.toggleFavorite(id: item.id)
                }
            } label: {
                // A ternary of string literals resolves to `String`, which
                // would pick Label's non-localized initializer — bind the key
                // to `LocalizedStringKey` first so it stays localizable.
                let starKey: LocalizedStringKey = item.isFavorite
                    ? "locpick_unfavorite" : "locpick_favorite"
                Label(starKey, systemImage: item.isFavorite ? "star.slash" : "star")
            }
            .tint(Color.brandWarning)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.2)) {
                    remembered = TaskLocationMemory.forget(id: item.id)
                }
            } label: {
                Label("locpick_delete", systemImage: "trash")
            }
        }
    }

    // MARK: Shared pieces

    private func sectionHeader(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .semibold))
            Text(title)
                .font(AppFont.scaled(12, weight: .semibold))
        }
        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        .textCase(nil)
    }

    private func placeLabel(title: String, subtitle: String,
                            icon: String, tint: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
    }

    /// The single selection path — every pick (search, free text, remembered,
    /// nearby, property, my position) is recorded here so Favorite/Frecvente/
    /// Recente reflect real usage and any pick can later be starred.
    private func select(_ value: TaskLocationValue) {
        TaskLocationMemory.remember(value)
        location = value
        HapticFeedback.impact(.light)
        dismiss()
    }

    /// A tapped completion resolves to a real map item — name + coordinates.
    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            defer { isResolving = false }
            let search = MKLocalSearch(request: MKLocalSearch.Request(completion: completion))
            guard let item = try? await search.start().mapItems.first else {
                // Apple couldn't resolve it — keep the visible name, no coords.
                select(TaskLocationValue(name: completion.title, lat: nil, lon: nil))
                return
            }
            let coord = item.placemark.coordinate
            select(TaskLocationValue(name: item.name ?? completion.title,
                                     lat: coord.latitude, lon: coord.longitude))
        }
    }
}

// MARK: - Detail page pieces (photo strip + location row)

/// Identifiable URL wrapper for the fullscreen viewer sheet (same pattern as
/// ShareURL in ElementPDFExporter — no retroactive conformance on URL).
private struct TaskPhotoURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct TaskDetailPhotoStrip: View {
    let urls: [String]
    @State private var viewerUrl: TaskPhotoURL?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(urls, id: \.self) { url in
                    Button {
                        if let u = URL(string: url) { viewerUrl = TaskPhotoURL(url: u) }
                    } label: {
                        AsyncImage(url: URL(string: url)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Color.primary.opacity(AppOpacity.subtleFill)
                            }
                        }
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $viewerUrl) { wrapped in
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    AsyncImage(url: wrapped.url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFit()
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { viewerUrl = nil }
                    }
                }
            }
        }
    }
}

struct TaskDetailLocationRow: View {
    let task: MaintenanceTask
    @State private var showNavigationOptions = false

    var body: some View {
        if let name = task.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            Button {
                guard task.locationLat != nil, task.locationLon != nil else { return }
                HapticFeedback.impact(.light)
                showNavigationOptions = true
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "mappin.circle.fill")
                        .font(AppFont.scaled(17))
                        .foregroundStyle(Color.brandDanger)
                    Text(verbatim: name)
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    // Only a real Apple Maps pick can open Maps — free text has
                    // no coordinates, so it shows without pretending to navigate.
                    if task.locationLat != nil, task.locationLon != nil {
                        Image(systemName: "arrow.up.right.square")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(task.locationLat == nil || task.locationLon == nil)
            // Same hand-off as chat's shared locations: Apple Maps always,
            // Google Maps / Waze via NavigationAppLauncher's universal-link
            // fallback — no Places API, no key, no new dependency.
            .confirmationDialog(Text("locpick_open_in"),
                                isPresented: $showNavigationOptions,
                                titleVisibility: .visible) {
                ForEach(NavigationAppLauncher.availableOptions()) { option in
                    Button(option.label) {
                        guard let lat = task.locationLat, let lon = task.locationLon else { return }
                        NavigationAppLauncher.open(option.id, lat: lat, lon: lon, label: name)
                    }
                }
            }
        }
    }
}
