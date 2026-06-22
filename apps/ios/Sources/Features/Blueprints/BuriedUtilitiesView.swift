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
        .navigationTitle("Underground")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
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
        Map(coordinateRegion: .constant(region), annotationItems: mapped) { u in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: u.latitude ?? 0, longitude: u.longitude ?? 0)) {
                ZStack {
                    Circle().fill(u.swiftColor).frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    Image(systemName: u.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .shadow(radius: 3)
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
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
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
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
                .font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.16))
            Text("No buried lines mapped")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
            Text("Record where you ran cables, water, gas or drainage underground — with depth and location — so you never dig blind again.")
                .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Spacer(minLength: 40)
        }
    }
}
