import SwiftUI
import MapKit
import CoreLocation

// MARK: - Public Contact Sheet

struct PublicContactSheet: View {
    let item: InventoryItem
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var ownerName: String
    @State private var ownerPhone: String
    @State private var ownerAddress: String
    @State private var propertyName: String
    @State private var isEnabled: Bool

    init(item: InventoryItem, onSave: @escaping (InventoryItem) -> Void) {
        self.item = item; self.onSave = onSave
        _ownerName    = State(initialValue: item.publicProfile?.ownerName ?? "")
        _ownerPhone   = State(initialValue: item.publicProfile?.ownerPhone ?? "")
        _ownerAddress = State(initialValue: item.publicProfile?.ownerAddress ?? "")
        _propertyName = State(initialValue: item.publicProfile?.propertyName ?? "")
        _isEnabled    = State(initialValue: item.publicProfile?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        GlassCard {
                            HStack(spacing: 12) {
                                Image(systemName: "qrcode.viewfinder").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                Text("Show on public QR page").font(AppFont.scaled(15)).foregroundStyle(.primary)
                                Spacer()
                                Toggle("", isOn: $isEnabled).tint(.accentColor).labelsHidden()
                            }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                        }
                        if isEnabled {
                            VStack(spacing: 0) {
                                pField("person.fill", "Your name", $ownerName)
                                div
                                pField("phone.fill", "Phone number", $ownerPhone, keyboard: .phonePad)
                                div
                                pField("house.fill", "Home address", $ownerAddress)
                                div
                                pField("building.fill", "Property name", $propertyName)
                            }
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                            Text("This information will be visible to anyone who scans the QR code of this item. Only share what you are comfortable with.")
                                .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                .multilineTextAlignment(.center).padding(.horizontal, AppSpacing.sm)
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Lost & Found Card").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        if isEnabled {
                            updated.publicProfile = PublicProfile(ownerName: ownerName, ownerPhone: ownerPhone,
                                                                  ownerAddress: ownerAddress, propertyName: propertyName, isEnabled: true)
                        } else {
                            updated.publicProfile = nil
                        }
                        onSave(updated); HapticFeedback.success(); dismiss()
                    }
                    .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private func pField(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(ph, text: b).font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }
    private var div: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }
}

// MARK: - Loan Sheet

struct LoanItemSheet: View {
    let onSave: (String, Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var borrower = ""
    @State private var hasReturnDate = false
    @State private var returnDate = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
                            TextField("Borrower's name", text: $borrower).font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.5).padding(.leading, 52)
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
                            Text("Expected return").font(AppFont.scaled(15)).foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: $hasReturnDate).tint(.accentColor).labelsHidden()
                        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                        if hasReturnDate {
                            Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.5).padding(.leading, 52)
                            HStack(spacing: 12) {
                                Color.clear.frame(width: 28)
                                DatePicker("Return by", selection: $returnDate, in: Date()..., displayedComponents: .date)
                                    .tint(.accentColor)
                            }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.sm)
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                    Text("You'll get reminders after 1, 3, 7, 14, 30 and 90 days if the item isn't returned.")
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.38))
                        .multilineTextAlignment(.center).padding(.horizontal, AppSpacing.sm)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.xl)
            }
            .navigationTitle("Loan Out Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onSave(borrower.trimmingCharacters(in: .whitespaces), hasReturnDate ? returnDate : nil)
                        HapticFeedback.success(); dismiss()
                    }
                    .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                    .disabled(borrower.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Location + Tracker Sheet

struct ItemLocationSheet: View {
    let item: InventoryItem
    let onSave: (InventoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var locMgr = LocationManager()

    @State private var latText: String
    @State private var lonText: String
    @State private var trackerType: String
    @State private var trackerIdentifier: String

    private let trackerTypes = ["", "airtag", "tile", "gps", "other"]

    init(item: InventoryItem, onSave: @escaping (InventoryItem) -> Void) {
        self.item = item; self.onSave = onSave
        _latText           = State(initialValue: item.latitude.map { String(format: "%.6f", $0) } ?? "")
        _lonText           = State(initialValue: item.longitude.map { String(format: "%.6f", $0) } ?? "")
        _trackerType       = State(initialValue: item.trackerType)
        _trackerIdentifier = State(initialValue: item.trackerIdentifier)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if let lat = Double(latText), let lon = Double(lonText) {
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                            ))) {
                                Marker("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                    .tint(.blue)
                            }
                            .frame(maxWidth: .infinity).frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                        }
                        Button { locMgr.requestLocation() } label: {
                            Label("Use Current Location", systemImage: "location.fill")
                                .font(AppFont.footnoteEmphasis).foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.md))
                        }.buttonStyle(.plain)
                        VStack(spacing: 0) {
                            coordRow("Latitude", $latText)
                            Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                            coordRow("Longitude", $lonText)
                        }
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TRACKER TYPE").font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).padding(.leading, AppSpacing.xxs)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(trackerTypes, id: \.self) { t in
                                        Button { trackerType = t } label: {
                                            Text(LocalizedStringKey(t.isEmpty ? "None" : (t == "airtag" ? "AirTag" : (t == "gps" ? "GPS" : t.capitalized))))
                                                .font(AppFont.scaled(13, weight: trackerType == t ? .semibold : .regular))
                                                .foregroundStyle(trackerType == t ? Color.black : Color.primary.opacity(AppOpacity.emphasis))
                                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                                                .background(trackerType == t ? Color.white : Color.primary.opacity(0.08), in: Capsule())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        if !trackerType.isEmpty {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    Image(systemName: "antenna.radiowaves.left.and.right").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
                                    TextField("Tracker name / serial (optional)", text: $trackerIdentifier)
                                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                                }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
                            }
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                            if trackerType == "airtag" {
                                GlassCard(padding: 14) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                                        Text("Apple AirTag live location requires the Find My app (private Apple API). Save the name here as a reference, then open Find My for live tracking.")
                                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.55))
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Location & Tracker").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        updated.latitude = Double(latText)
                        updated.longitude = Double(lonText)
                        updated.trackerType = trackerType
                        updated.trackerIdentifier = trackerIdentifier
                        onSave(updated)
                        HapticFeedback.success()
                        dismiss()
                    }.font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
            .onChange(of: locMgr.location) { _, loc in
                guard let loc else { return }
                latText = String(format: "%.6f", loc.coordinate.latitude)
                lonText = String(format: "%.6f", loc.coordinate.longitude)
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private func coordRow(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill").font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(label).font(AppFont.scaled(15)).foregroundStyle(.primary)
            Spacer()
            TextField("0.000000", text: binding).font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).tint(.accentColor)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }
}
