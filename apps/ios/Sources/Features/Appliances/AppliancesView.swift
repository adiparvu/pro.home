import SwiftUI

// MARK: - AppliancesView

struct AppliancesView: View {
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PropertyService.self) private var propertyService

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
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search appliances…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add appliance")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddApplianceSheet()
                .environment(applianceService)
                .environment(propertyService)
        }
        .sheet(item: $selectedAppliance) { appliance in
            ApplianceDetailSheet(appliance: appliance)
                .environment(applianceService)
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
                if !applianceService.appliancesExpiringWarranty.isEmpty {
                    warrantyBanner
                }
                categoryChips
                if filtered.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                } else {
                    appliances
                }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await applianceService.load(propertyId: id)
            }
        }
    }

    private var warrantyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.orange)
            Text("\(applianceService.appliancesExpiringWarranty.count) warranty expiring soon")
                .font(AppFont.footnote)
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8)
        )
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: String(localized: "All"), isSelected: selectedCategory == nil) {
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

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: label)
                .font(AppFont.scaled(13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.primary.opacity(AppOpacity.emphasis))
                .padding(.horizontal, AppSpacing.base)
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
        EmptyStateView(
            icon: "cube.box.fill",
            title: "No appliances yet",
            message: "Track warranties, model numbers, and maintenance for all your home appliances.",
            actionLabel: "Add your first appliance",
            action: { showAdd = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if let brand = appliance.brand, !brand.isEmpty {
                            Text(brand)
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        }
                        if let model = appliance.modelNumber, !model.isEmpty {
                            if appliance.brand?.isEmpty == false {
                                Text("·").foregroundStyle(Color.primary.opacity(0.2))
                            }
                            Text(model)
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(appliance.warrantyStatus)
                            .font(AppFont.caption2)
                            .foregroundStyle(appliance.warrantyColor)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 3)
                            .background(appliance.warrantyColor.opacity(0.12), in: Capsule())

                        if let location = appliance.location, !location.isEmpty {
                            Text(location)
                                .font(AppFont.scaled(11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(AppOpacity.hairline), in: Capsule())
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
    }
}
