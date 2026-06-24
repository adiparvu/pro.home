import SwiftUI

// MARK: - AppliancesView

struct AppliancesView: View {
    @EnvironmentObject private var applianceService: ApplianceService
    @EnvironmentObject private var propertyService: PropertyService

    @State private var showAdd = false
    @State private var selectedAppliance: Appliance? = nil
    @State private var search = ""
    @State private var selectedCategory: ApplianceCategory? = nil

    private var filtered: [Appliance] {
        var list = selectedCategory == nil
            ? applianceService.appliances
            : selectedCategory.flatMap { applianceService.byCategory[$0] } ?? []
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                ($0.brand?.localizedCaseInsensitiveContains(search) ?? false) ||
                ($0.location?.localizedCaseInsensitiveContains(search) ?? false)
            }
        }
        return list
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if applianceService.isLoading && applianceService.appliances.isEmpty {
                    loadingState
                } else if applianceService.appliances.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
        }
        .navigationTitle("Appliances")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddApplianceSheet()
                .environmentObject(applianceService)
                .environmentObject(propertyService)
        }
        .sheet(item: $selectedAppliance) { appliance in
            ApplianceDetailSheet(appliance: appliance)
                .environmentObject(applianceService)
        }
        .task {
            if let id = propertyService.primary?.id {
                await applianceService.load(propertyId: id)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                searchBar
                if !applianceService.appliancesExpiringWarranty.isEmpty {
                    warrantyBanner
                }
                categoryChips
                appliances
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await applianceService.load(propertyId: id)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Search appliances…", text: $search)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var warrantyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
            Text("\(applianceService.appliancesExpiringWarranty.count) warranty expiring soon")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8)
        )
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                    HapticFeedback.impact(.light)
                }
                ForEach(ApplianceCategory.allCases, id: \.self) { cat in
                    chip(label: cat.displayName, isSelected: selectedCategory == cat) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                        HapticFeedback.impact(.light)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(label: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var appliances: some View {
        LazyVStack(spacing: 10) {
            ForEach(filtered) { appliance in
                ApplianceRow(appliance: appliance)
                    .onTapGesture {
                        selectedAppliance = appliance
                        HapticFeedback.impact(.light)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            HapticFeedback.warning()
                            Task { await applianceService.delete(appliance) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cube.box.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("No appliances yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Track warranties, model numbers, and maintenance for all your home appliances.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add your first appliance", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ApplianceRow

private struct ApplianceRow: View {
    let appliance: Appliance

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: appliance.categoryIcon, color: appliance.categoryColor, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appliance.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if let brand = appliance.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.45))
                        }
                        if let model = appliance.modelNumber, !model.isEmpty {
                            if appliance.brand?.isEmpty == false {
                                Text("·").foregroundStyle(Color.primary.opacity(0.2))
                            }
                            Text(model)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.35))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(appliance.warrantyStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(appliance.warrantyColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(appliance.warrantyColor.opacity(0.12), in: Capsule())

                        if let location = appliance.location, !location.isEmpty {
                            Text(location)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
    }
}
