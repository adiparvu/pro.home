import SwiftUI
import MapKit
import CoreLocation
import PhotosUI

// MARK: - Row

struct BuriedUtilityRow: View {
    let utility: BuriedUtility
    let photo: UIImage?

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(utility.swiftColor.opacity(0.2))
                        .overlay(Circle().strokeBorder(utility.swiftColor.opacity(0.5), lineWidth: 1.5))
                    Image(systemName: utility.icon)
                        .font(AppFont.headline)
                        .foregroundStyle(utility.swiftColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(utility.name)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(utility.typeLabel))
                            .font(AppFont.caption2)
                            .foregroundStyle(utility.swiftColor)
                        Text("·").foregroundStyle(Color.primary.opacity(0.3))
                        Text(LocalizedStringKey(utility.depthDisplay))
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        if utility.lengthM > 0 {
                            Text("·").foregroundStyle(Color.primary.opacity(0.3))
                            Text(LocalizedStringKey(utility.lengthDisplay))
                                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        }
                    }
                }
                Spacer()
                if photo != nil {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.3))
                }
                if utility.hasLocation {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
    }
}

// MARK: - Detail Sheet

struct BuriedUtilityDetailSheet: View {
    let utility: BuriedUtility
    let photo: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let photo {
                            Image(uiImage: photo)
                                .resizable().scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        if utility.hasLocation {
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: utility.latitude ?? 0, longitude: utility.longitude ?? 0),
                                span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)
                            ))) {
                                Marker("", coordinate: CLLocationCoordinate2D(latitude: utility.latitude ?? 0, longitude: utility.longitude ?? 0))
                                    .tint(utility.swiftColor)
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
                                    Text("NOTES").font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                    Text(utility.notes).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if utility.hasLocation {
                            Button {
                                let coord = "\(utility.latitude ?? 0),\(utility.longitude ?? 0)"
                                if let url = URL(string: "maps://?q=\(coord)&ll=\(coord)") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open in Maps", systemImage: "map.fill")
                                    .font(AppFont.subheadline).foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.base)
                                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle(utility.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String, color: Color = .white) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
            Text(LocalizedStringKey(value)).font(AppFont.footnoteEmphasis).foregroundStyle(color)
        }
        .padding(.vertical, 10)
    }

    private var divider: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5) }

    private func dateString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
    }
}

// MARK: - Add Sheet

struct AddBuriedUtilitySheet: View {
    let onSave: (BuriedUtility, Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var locMgr = LocationManager()

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
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        typePicker
                        fields
                        locationCard
                        dateCard
                        photoCard
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Add Buried Line").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(AppFont.subheadline)
                        .foregroundStyle(name.isEmpty ? Color.primary.opacity(0.3) : Color.accentColor)
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
        .presentationBackground(.thinMaterial)
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TYPE").font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).padding(.leading, AppSpacing.xxs)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BuriedUtilityKind.all, id: \.self) { t in
                        Button { type = t } label: {
                            HStack(spacing: 5) {
                                Image(systemName: BuriedUtilityKind.icon(t)).font(.system(size: 11))
                                Text(LocalizedStringKey(BuriedUtilityKind.label(t))).font(.system(size: 13, weight: type == t ? .semibold : .regular))
                            }
                            .foregroundStyle(type == t ? Color.black : Color.primary.opacity(AppOpacity.emphasis))
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                            .background(type == t ? BuriedUtilityKind.color(t) : Color.primary.opacity(0.08), in: Capsule())
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
                Image(systemName: "arrow.down.to.line").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                Text("Depth (cm)").font(.system(size: 15)).foregroundStyle(.primary)
                Spacer()
                TextField("60", text: $depth)
                    .font(AppFont.subheadline).foregroundStyle(.primary).tint(.accentColor)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
            div
            HStack(spacing: 12) {
                Image(systemName: "ruler").font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
                Text("Length (m)").font(.system(size: 15)).foregroundStyle(.primary)
                Spacer()
                TextField("0", text: $length)
                    .font(AppFont.subheadline).foregroundStyle(.primary).tint(.accentColor)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
            div
            fieldRow("note.text", "Notes (distances, landmarks…)", $notes)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
    }

    private var locationCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Toggle(isOn: $tagLocation) {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(.red)
                        Text("Tag current location").font(.system(size: 15)).foregroundStyle(.primary)
                    }
                }
                .tint(.accentColor)
                .onChange(of: tagLocation) { _, on in
                    if on { locMgr.requestLocation() }
                }
                if tagLocation {
                    if let loc = locMgr.location {
                        Text(String(format: "📍 %.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                            .font(.system(size: 12)).foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(LocalizedStringKey(locMgr.denied ? "Location denied — enable in Settings." : "Getting location…"))
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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
                        Image(systemName: "calendar").foregroundStyle(Color.accentColor)
                        Text("Installation date").font(.system(size: 15)).foregroundStyle(.primary)
                    }
                }.tint(.accentColor)
                if useInstalledDate {
                    DatePicker("Date", selection: $installedDate, displayedComponents: [.date])
                        .font(.system(size: 14)).foregroundStyle(.primary).tint(.accentColor)
                }
            }
        }
    }

    private var photoCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                if let img = photoImage {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 160).clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                Button { showPhotoPicker = true } label: {
                    Label(LocalizedStringKey(photoImage == nil ? "Add reference photo" : "Change photo"), systemImage: "photo.badge.plus")
                        .font(AppFont.footnote).foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
        }
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(placeholder, text: text).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    private var div: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

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
