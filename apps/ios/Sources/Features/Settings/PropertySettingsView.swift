import SwiftUI
import MapKit
import CoreLocation
import PhotosUI

struct PropertySettingsView: View {
    @Environment(PropertyService.self) private var propertyService
    @State private var showAdd = false
    @State private var showSearch = false
    @State private var searchText = ""

    private var filteredProperties: [PropertyModel] {
        propertyService.properties.filter {
            $0.name.matchesSearch(searchText) ||
            $0.addressLine1.matchesSearch(searchText) ||
            $0.city.matchesSearch(searchText) ||
            $0.propertyType.matchesSearch(searchText)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if propertyService.properties.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredProperties) { p in
                        NavigationLink {
                            PropertyDetailView(propertyId: p.id)
                                .environment(propertyService)
                        } label: {
                            propertyCard(p)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("My Property")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, isPresented: $showSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    SearchIconButton(isActive: $showSearch)
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("Add property")
                }
            }
        }
        .onChange(of: showSearch) { _, on in
            if !on { searchText = "" }
        }
        .sheet(isPresented: $showAdd) { AddPropertySheet() }
        .alert("Error", isPresented: Binding(
            get: { propertyService.error != nil },
            set: { if !$0 { propertyService.error = nil } }
        )) {
            Button("OK") { propertyService.error = nil }
        } message: {
            Text(LocalizedStringKey(propertyService.error ?? ""))
        }
        .task { await propertyService.load() }
    }

    // MARK: - Property card

    private func propertyCard(_ p: PropertyModel) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                propertyThumb(p)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("\(p.addressLine1), \(p.city)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(p.propertyType.capitalized))
                            .font(AppFont.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                            .background(.blue.opacity(0.15), in: Capsule())
                        if let score = p.healthScore {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(.red.opacity(0.7))
                                Text("\(score)").font(AppFont.label).foregroundStyle(Color.primary.opacity(0.6))
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
    }

    @ViewBuilder
    private func propertyThumb(_ p: PropertyModel) -> some View {
        if let urlStr = p.photoUrl, let url = URL(string: urlStr) {
            StorageImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { thumbPlaceholder }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            thumbPlaceholder.frame(width: 56, height: 56)
        }
    }

    private var thumbPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "house.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)
            EmptyStateView(
                icon: "house.circle",
                title: "No property found",
                message: "Your property data will appear here once it's configured."
            )
        }
    }
}

// MARK: - Detail row (shared with PropertyDetailView)

struct PropDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
            Text(value)
                .font(AppFont.footnote)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, AppSpacing.base)
    }
}
