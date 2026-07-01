import SwiftUI

// MARK: - DeliveriesView

struct DeliveriesView: View {
    @EnvironmentObject private var deliveryService: DeliveryService
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    @State private var showAddDelivery = false
    @State private var editingDelivery: Delivery? = nil
    @State private var showCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(titleKey: "Deliveries", subtitleKey: "PROPERTY")

            if deliveryService.deliveries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddDelivery = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.title3)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add delivery")
            }
        }
        .sheet(isPresented: $showAddDelivery) {
            DeliveryFormSheet(editingDelivery: nil)
                .environmentObject(deliveryService)
        }
        .sheet(item: $editingDelivery) { delivery in
            DeliveryFormSheet(editingDelivery: delivery)
                .environmentObject(deliveryService)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryPill

                if !deliveryService.activeDeliveries.isEmpty {
                    activeSection
                }

                completedSection

                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("deliveriesScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "deliveriesScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            tabBarVis.scrollOffset = y
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.2, green: 0.80, blue: 0.4))
                    .frame(width: 8, height: 8)
                Text("\(delivered) delivered")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            if !deliveryService.todayDeliveries.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 14)
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
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
                Text("IN PROGRESS · \(deliveryService.activeDeliveries.count)")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 10) {
                ForEach(deliveryService.activeDeliveries) { delivery in
                    DeliveryRow(delivery: delivery) {
                        editingDelivery = delivery
                    }
                    .environmentObject(deliveryService)
                }
            }
        }
    }

    // MARK: - Completed section

    private var completedSection: some View {
        let completed = deliveryService.deliveries.filter { !$0.isActive }
        guard !completed.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35)) { showCompleted.toggle() }
                    HapticFeedback.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("DELIVERED · \(completed.count)")
                            .font(AppFont.label)
                            .tracking(0.5)
                        Spacer()
                    }
                    .foregroundStyle(Color(red: 0.2, green: 0.80, blue: 0.4))
                    .padding(.leading, AppSpacing.xxs)
                }
                .buttonStyle(.plain)

                if showCompleted {
                    VStack(spacing: 10) {
                        ForEach(completed) { delivery in
                            DeliveryRow(delivery: delivery) {
                                editingDelivery = delivery
                            }
                            .environmentObject(deliveryService)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No deliveries tracked")
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Add packages to track\nyour deliveries.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
            Button { showAddDelivery = true } label: {
                Label("Add first delivery", systemImage: "plus")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - DeliveryRow

struct DeliveryRow: View {
    @EnvironmentObject private var deliveryService: DeliveryService
    let delivery: Delivery
    let onEdit: () -> Void

    var body: some View {
        GlassCard(padding: 14) {
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
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        if let tn = delivery.trackingNumber, !tn.isEmpty {
                            Text("·")
                                .foregroundStyle(Color.primary.opacity(0.3))
                            Text(tn)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                .lineLimit(1)
                        }
                    }

                    if let expected = delivery.expectedDisplay {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            Text(expected)
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    expected == "Today"
                                        ? Color.orange
                                        : Color.primary.opacity(0.4)
                                )
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
