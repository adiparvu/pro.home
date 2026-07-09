import SwiftUI
import MapKit
import CoreLocation
import PhotosUI

struct BuriedUtilitiesView: View {
    var service: BlueprintService
    @State private var showAdd = false
    @State private var detailItem: BuriedUtility?
    @State private var searchText = ""

    private var mapped: [BuriedUtility] { service.utilities.filter { $0.hasLocation } }

    private var filteredUtilities: [BuriedUtility] {
        guard !searchText.isEmpty else { return service.utilities }
        return service.utilities.filter {
            $0.name.matchesSearch(searchText)
                || $0.typeLabel.matchesSearch(searchText)
                || $0.notes.matchesSearch(searchText)
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if !mapped.isEmpty {
                            mapCard
                        }
                        if service.utilities.isEmpty {
                            emptyState
                        } else {
                            legend
                            ForEach(filteredUtilities) { u in
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
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, 110)
                }
            }
        }
        .navigationTitle("Underground")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add buried line")
            }
        }
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
        Map(initialPosition: .region(region)) {
            ForEach(mapped) { u in
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: u.latitude ?? 0, longitude: u.longitude ?? 0)) {
                    ZStack {
                        Circle().fill(u.swiftColor).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        Image(systemName: u.icon)
                            .font(AppFont.scaled(12, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .shadow(radius: 3)
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
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
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: first, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.002),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.002)
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
                        Text(LocalizedStringKey(BuriedUtilityKind.label(t)))
                            .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
            title: "No buried lines mapped",
            message: "Record where you ran cables, water, gas or drainage underground — with depth and location — so you never dig blind again."
        )
    }
}
