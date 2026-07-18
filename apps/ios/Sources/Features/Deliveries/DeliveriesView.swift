import SwiftUI

// MARK: - DeliveriesView

struct DeliveriesView: View {
    @Environment(DeliveryService.self) private var deliveryService

    @State private var showAddDelivery = false
    @State private var editingDelivery: Delivery? = nil
    @State private var showCompleted = false
    @State private var showAutoImport = false
    @State private var searchText = ""

    private var filteredActiveDeliveries: [Delivery] {
        deliveryService.activeDeliveries.filter(matchesSearch)
    }

    private var filteredCompletedDeliveries: [Delivery] {
        deliveryService.deliveries.filter { !$0.isActive && matchesSearch($0) }
    }

    private func matchesSearch(_ delivery: Delivery) -> Bool {
        delivery.description.matchesSearch(searchText)
            || (delivery.carrier ?? "").matchesSearch(searchText)
            || (delivery.trackingNumber ?? "").matchesSearch(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            if deliveryService.deliveries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Deliveries")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAutoImport = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "envelope.badge")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Auto-import from email")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddDelivery = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add delivery")
            }
        }
        .sheet(isPresented: $showAddDelivery) {
            DeliveryFormSheet(editingDelivery: nil)
                .environment(deliveryService)
        }
        .sheet(isPresented: $showAutoImport) {
            AutoImportView()
                .environment(deliveryService)
        }
        .sheet(item: $editingDelivery) { delivery in
            DeliveryFormSheet(editingDelivery: delivery)
                .environment(deliveryService)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryPill

                if !searchText.isEmpty && filteredActiveDeliveries.isEmpty && filteredCompletedDeliveries.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                }

                if !filteredActiveDeliveries.isEmpty {
                    activeSection
                }

                completedSection

                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
        .refreshable {
            if let pid = PropertyService.activePropertyId {
                await deliveryService.load(propertyId: pid)
            }
        }
    }

    // MARK: - Summary pill

    private var summaryPill: some View {
        let active = deliveryService.activeDeliveries.count
        let delivered = deliveryService.deliveries.filter { !$0.isActive }.count
        return HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                Text("\(active) active")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.brandSuccess)
                    .frame(width: 8, height: 8)
                Text("\(delivered) delivered")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            if !deliveryService.todayDeliveries.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 14)
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(AppFont.scaled(10))
                        .foregroundStyle(.orange)
                    Text("\(deliveryService.todayDeliveries.count) today")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassCapsule()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Active section

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(AppFont.label)
                    .foregroundStyle(Color.accentColor)
                Text("IN PROGRESS · \(filteredActiveDeliveries.count)")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.leading, AppSpacing.xxs)

            LazyVStack(spacing: 10) {
                ForEach(filteredActiveDeliveries) { delivery in
                    NavigationLink {
                        DeliveryDetailView(delivery: delivery) { editingDelivery = delivery }
                            .environment(deliveryService)
                    } label: {
                        DeliveryRow(delivery: delivery) { editingDelivery = delivery }
                            .environment(deliveryService)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Completed section

    @ViewBuilder
    private var completedSection: some View {
        let completed = filteredCompletedDeliveries
        if !completed.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35)) { showCompleted.toggle() }
                    HapticFeedback.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                            .font(AppFont.scaled(10, weight: .semibold))
                        Text("DELIVERED · \(completed.count)")
                            .font(AppFont.label)
                            .tracking(0.5)
                        Spacer()
                    }
                    .foregroundStyle(Color.brandSuccess)
                    .padding(.leading, AppSpacing.xxs)
                }
                .buttonStyle(.plain)

                if showCompleted {
                    LazyVStack(spacing: 10) {
                        ForEach(completed) { delivery in
                            NavigationLink {
                                DeliveryDetailView(delivery: delivery) { editingDelivery = delivery }
                                    .environment(deliveryService)
                            } label: {
                                DeliveryRow(delivery: delivery) { editingDelivery = delivery }
                                    .environment(deliveryService)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(AppFont.scaled(56))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No deliveries tracked")
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Add packages to track\nyour deliveries.")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
            Button { showAddDelivery = true } label: {
                Label("Add first delivery", systemImage: "plus")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .glassProminent(in: Capsule())
            }
            .buttonStyle(.plain)
            // The auto-import superpower — surfaced here so it isn't hidden
            // behind the toolbar envelope on an empty screen.
            Button { showAutoImport = true; HapticFeedback.impact(.light) } label: {
                Label("deliv_import_cta", systemImage: "envelope.badge")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Delivery progress bar
//
// The parcel's journey as four filling segments — Info received → In transit →
// Out for delivery → Delivered — driven by the live tracking status when the
// aggregator is following it, otherwise by the manual status. An exception
// turns the first segment red so a problem reads at a glance.
struct DeliveryProgressBar: View {
    let delivery: Delivery

    var body: some View {
        let stage = delivery.progressStage
        let exception = delivery.hasException
        HStack(spacing: 3) {
            ForEach(0..<Delivery.journeyStages, id: \.self) { i in
                Capsule()
                    .fill(fill(for: i, stage: stage, exception: exception))
                    .frame(height: 3)
            }
        }
        .animation(.smooth(duration: 0.3), value: stage)
        .accessibilityElement()
        .accessibilityLabel(Text(delivery.liveStatusLabel ?? delivery.statusLabel))
    }

    private func fill(for index: Int, stage: Int, exception: Bool) -> Color {
        if exception { return index == 0 ? Color.brandDanger : Color.primary.opacity(0.1) }
        return index <= stage ? delivery.statusColor : Color.primary.opacity(0.1)
    }
}

// MARK: - DeliveryRow

struct DeliveryRow: View {
    @Environment(DeliveryService.self) private var deliveryService
    let delivery: Delivery
    let onEdit: () -> Void

    var body: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(delivery.statusColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: delivery.statusIcon)
                            .font(AppFont.title3)
                            .foregroundStyle(delivery.statusColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(delivery.description)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            if let carrier = delivery.carrier, !carrier.isEmpty {
                                Text(carrier)
                                    .font(AppFont.scaled(12))
                                    .foregroundStyle(.secondary)
                            }

                            if let tn = delivery.trackingNumber, !tn.isEmpty {
                                Text("·")
                                    .foregroundStyle(Color.primary.opacity(0.3))
                                Text(tn)
                                    .font(AppFont.scaled(12, design: .monospaced))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                    .lineLimit(1)
                            }
                        }

                        // The courier's own live status wins when it's tracking;
                        // otherwise the expected/entered arrival date.
                        HStack(spacing: 4) {
                            Image(systemName: delivery.isLiveTracked ? "dot.radiowaves.up.forward" : "calendar")
                                .font(AppFont.scaled(10))
                                .foregroundStyle(delivery.isLiveTracked ? delivery.statusColor : Color.primary.opacity(AppOpacity.disabled))
                            if let live = delivery.liveStatusLabel {
                                Text(live)
                                    .font(AppFont.scaled(11, weight: .medium))
                                    .foregroundStyle(delivery.statusColor)
                                if let eta = delivery.etaDisplay {
                                    Text("· \(eta)")
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(Color.primary.opacity(0.4))
                                }
                            } else if let eta = delivery.etaDisplay {
                                Text(eta)
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(eta == String(localized: "Today") ? Color.orange
                                                     : Color.primary.opacity(0.4))
                            }
                        }
                    }

                    Spacer()

                    Text(LocalizedStringKey(delivery.statusLabel))
                        .font(AppFont.label)
                        .foregroundStyle(delivery.statusColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            delivery.statusColor.opacity(0.13),
                            in: Capsule()
                        )
                }

                // The journey, at a glance — only while the parcel is on its way.
                if delivery.isActive {
                    DeliveryProgressBar(delivery: delivery)
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if delivery.isActive {
                Button {
                    HapticFeedback.success()
                    Task { await deliveryService.markDelivered(delivery) }
                } label: {
                    Label("Delivered", systemImage: "checkmark.seal.fill")
                }
                .tint(Color(red: 0.2, green: 0.78, blue: 0.4))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await deliveryService.delete(delivery) }
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                HapticFeedback.impact(.light)
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.accentColor)
        }
        .contextMenu {
            if delivery.isActive {
                Button {
                    HapticFeedback.success()
                    Task { await deliveryService.markDelivered(delivery) }
                } label: {
                    Label("Mark as delivered", systemImage: "checkmark.seal.fill")
                }
            }

            Button {
                HapticFeedback.impact(.light)
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if let tn = delivery.trackingNumber, !tn.isEmpty {
                Button {
                    UIPasteboard.general.string = tn
                    HapticFeedback.selection()
                } label: {
                    Label("Copy tracking", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await deliveryService.delete(delivery) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
