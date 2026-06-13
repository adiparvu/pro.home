import SwiftUI
import MapKit
import CoreLocation
import PhotosUI

struct BuriedUtilitiesView: View {
    @ObservedObject var service: BlueprintService
    @State private var showAdd = false
    @State private var detailItem: BuriedUtility?

    private var mapped: [BuriedUtility] { service.utilities.filter { $0.hasLocation } }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(
                    title: "Underground",
                    trailing: AnyView(
                        Button {
                            showAdd = true
                            HapticFeedback.impact(.medium)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                        }
                    )
                )
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if !mapped.isEmpty {
                            mapCard
                        }
                        if service.utilities.isEmpty {
                            emptyState
                        } else {
                            legend
                            ForEach(service.utilities) { u in
                                BuriedUtilityRow(utility: u, photo: service.utilityPhoto(u))
                                    .onTapGesture { detailItem = u }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            service.deleteUtility(u)
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            AddBuriedUtilitySheet { utility, photo in
                service.addUtility(utility, photo: photo)
            }
        }
        .sheet(item: $detailItem) { u in
            BuriedUtilityDetailSheet(utility: u, photo: service.utilityPhoto(u))
        }
    }

    private var mapCard: some View {
        Map(coordinateRegion: .constant(region), annotationItems: mapped) { u in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: u.latitude!, longitude: u.longitude!)) {
                ZStack {
                    Circle().fill(u.swiftColor).frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    Image(systemName: u.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(radius: 3)
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }

    private var region: MKCoordinateRegion {
        let coords = mapped.compactMap { u -> CLLocationCoordinate2D? in
            guard let lat = u.latitude, let lon = u.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard let first = coords.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.002),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.5, 0.002)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                let used = Set(service.utilities.map(\.type))
                ForEach(BuriedUtilityKind.all.filter { used.contains($0) }, id: \.self) { t in
                    HStack(spacing: 5) {
                        Circle().fill(BuriedUtilityKind.color(t)).frame(width: 8, height: 8)
                        Text(BuriedUtilityKind.label(t))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 44)).foregroundStyle(.white.opacity(0.16))
            Text("No buried lines mapped")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Text("Record where you ran cables, water, gas or drainage underground — with depth and location — so you never dig blind again.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Row

private struct BuriedUtilityRow: View {
    let utility: BuriedUtility
    let photo: UIImage?

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(utility.swiftColor.opacity(0.2))
                        .overlay(Circle().strokeBorder(utility.swiftColor.opacity(0.5), lineWidth: 1.5))
                    Image(systemName: utility.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(utility.swiftColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(utility.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Text(utility.typeLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(utility.swiftColor)
                        Text("·").foregroundStyle(.white.opacity(0.3))
                        Text(utility.depthDisplay)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        if utility.lengthM > 0 {
                            Text("·").foregroundStyle(.white.opacity(0.3))
                            Text(utility.lengthDisplay)
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }
                Spacer()
                if photo != nil {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                }
                if utility.hasLocation {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }
}

// MARK: - Detail sheet

private struct BuriedUtilityDetailSheet: View {
    let utility: BuriedUtility
    let photo: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let photo {
                            Image(uiImage: photo)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        if utility.hasLocation {
                            Map(coordinateRegion: .constant(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: utility.latitude!, longitude: utility.longitude!),
                                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                            )), annotationItems: [utility]) { u in
                                MapMarker(coordinate: CLLocationCoordinate2D(latitude: u.latitude!, longitude: u.longitude!), tint: u.swiftColor)
                            }
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        GlassCard {
                            VStack(spacing: 0) {
                                detailRow("Type", utility.typeLabel, color: utility.swiftColor)
                                divider
                                detailRow("Depth", utility.depthDisplay)
                                if utility.lengthM > 0 {
                                    divider
                                    detailRow("Length", utility.lengthDisplay)
                                }
                                if let date = utility.installedDate {
                                    divider
                                    detailRow("Installed", dateString(date))
                                }
                            }
                        }
                        if !utility.notes.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("NOTES").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
                                    Text(utility.notes).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if utility.hasLocation {
                            Button {
                                let coord = "\(utility.latitude!),\(utility.longitude!)"
                                if let url = URL(string: "maps://?q=\(coord)&ll=\(coord)") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open in Maps", systemImage: "map.fill")
                                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle(utility.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue)
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, color: Color = .white) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 10)
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5) }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
    }
}

// MARK: - Add sheet

private struct AddBuriedUtilitySheet: View {
    let onSave: (BuriedUtility, Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locMgr = LocationManager()

    @State private var name = ""
    @State private var type = "electrical"
    @State private var depth = ""
    @State private var length = ""
    @State private var notes = ""
    @State private var tagLocation = false
    @State private var useInstalledDate = false
    @State private var installedDate = Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoImage: UIImage?
    @State private var showPhotoPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        typePicker
                        fields
                        locationCard
                        dateCard
                        photoCard
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Buried Line").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(name.isEmpty ? .white.opacity(0.3) : .blue)
                        .disabled(name.isEmpty)
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run { photoData = data; photoImage = UIImage(data: data) }
                    }
                }
            }
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TYPE").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BuriedUtilityKind.all, id: \.self) { t in
                        Button { type = t } label: {
                            HStack(spacing: 5) {
                                Image(systemName: BuriedUtilityKind.icon(t)).font(.system(size: 11))
                                Text(BuriedUtilityKind.label(t)).font(.system(size: 13, weight: type == t ? .semibold : .regular))
                            }
                            .foregroundStyle(type == t ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(type == t ? BuriedUtilityKind.color(t) : .white.opacity(0.08), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            fieldRow("textformat", "Name (e.g. Main power cable)", $name)
            div
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                Text("Depth (cm)").font(.system(size: 15)).foregroundStyle(.white)
                Spacer()
                TextField("60", text: $depth)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).tint(.blue)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            }.padding(.horizontal, 16).padding(.vertical, 13)
            div
            HStack(spacing: 12) {
                Image(systemName: "ruler").font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
                Text("Length (m)").font(.system(size: 15)).foregroundStyle(.white)
                Spacer()
                TextField("0", text: $length)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).tint(.blue)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            }.padding(.horizontal, 16).padding(.vertical, 13)
            div
            fieldRow("note.text", "Notes (distances, landmarks…)", $notes)
        }
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    private var locationCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Toggle(isOn: $tagLocation) {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        Text("Tag current location").font(.system(size: 15)).foregroundStyle(.white)
                    }
                }
                .tint(.blue)
                .onChange(of: tagLocation) { _, on in
                    if on { locMgr.requestLocation() }
                }
                if tagLocation {
                    if let loc = locMgr.location {
                        Text(String(format: "📍 %.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                            .font(.system(size: 12)).foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(locMgr.denied ? "Location denied — enable in Settings." : "Getting location…")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var dateCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Toggle(isOn: $useInstalledDate) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar").foregroundStyle(.blue)
                        Text("Installation date").font(.system(size: 15)).foregroundStyle(.white)
                    }
                }.tint(.blue)
                if useInstalledDate {
                    DatePicker("Date", selection: $installedDate, displayedComponents: [.date])
                        .font(.system(size: 14)).foregroundStyle(.white).tint(.blue)
                }
            }
        }
    }

    private var photoCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                if let img = photoImage {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button { showPhotoPicker = true } label: {
                    Label(photoImage == nil ? "Add reference photo" : "Change photo", systemImage: "photo.badge.plus")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.blue)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
            TextField(placeholder, text: text).font(.system(size: 15)).foregroundStyle(.white).tint(.blue)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var div: some View { Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

    private func save() {
        let loc = tagLocation ? locMgr.location : nil
        let utility = BuriedUtility(
            name: name,
            type: type,
            depthCm: Double(depth.replacingOccurrences(of: ",", with: ".")) ?? 0,
            lengthM: Double(length.replacingOccurrences(of: ",", with: ".")) ?? 0,
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude,
            notes: notes,
            installedDate: useInstalledDate ? installedDate : nil
        )
        onSave(utility, photoData)
        HapticFeedback.success()
        dismiss()
    }
}
