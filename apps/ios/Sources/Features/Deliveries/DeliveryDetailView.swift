import SwiftUI

// MARK: - Delivery detail with live tracking timeline
//
// Renders purely from our own normalized fields (live_status, checkpoints, ETA)
// written by the tracking webhook — it never knows which aggregator produced
// them, so the provider can change without touching this screen.

struct DeliveryDetailView: View {
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(\.dismiss) private var dismiss

    private let deliveryId: UUID
    private let initial: Delivery
    private let onEdit: () -> Void

    @State private var isRefreshing = false

    init(delivery: Delivery, onEdit: @escaping () -> Void) {
        self.deliveryId = delivery.id
        self.initial = delivery
        self.onEdit = onEdit
    }

    /// Always read the freshest copy from the service so live updates reflect.
    private var delivery: Delivery {
        deliveryService.deliveries.first { $0.id == deliveryId } ?? initial
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xl) {
                hero
                liveStatusCard
                timelineCard
                actions
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { onEdit() } label: {
                    Image(systemName: "pencil").font(AppFont.headline).foregroundStyle(.primary)
                }
                .accessibilityLabel("Edit")
            }
        }
        .refreshable { await refresh() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: delivery.statusIcon)
                .font(AppFont.scaled(32, weight: .semibold))
                .foregroundStyle(delivery.statusColor)
                .frame(width: 76, height: 76)
                .glassCircle()
            VStack(spacing: 4) {
                Text(delivery.description)
                    .font(AppFont.title2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let carrier = delivery.carrier, !carrier.isEmpty {
                    Text(carrier)
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            statusPill
            if let tn = delivery.trackingNumber, !tn.isEmpty {
                Button {
                    UIPasteboard.general.string = tn
                    HapticFeedback.selection()
                } label: {
                    HStack(spacing: 6) {
                        Text(tn).font(AppFont.scaled(13, weight: .medium, design: .monospaced))
                        Image(systemName: "doc.on.doc").font(AppFont.scaled(11))
                    }
                    .foregroundStyle(Color.secondaryTextColor)
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
                    .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.sm)
    }

    private var statusPill: some View {
        Text(LocalizedStringKey(liveStatusLabel))
            .font(AppFont.captionEmphasis)
            .foregroundStyle(delivery.statusColor)
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 5)
            .background(delivery.statusColor.opacity(0.14), in: Capsule())
    }

    // MARK: - Live status card

    private var liveStatusCard: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(AppFont.footnote).foregroundStyle(Color.brandSuccess)
                    Text("Live tracking").font(AppFont.captionStrong).foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    if delivery.isLiveTracked {
                        Text(LocalizedStringKey(liveStatusLabel))
                            .font(AppFont.captionEmphasis).foregroundStyle(delivery.statusColor)
                    }
                }

                if delivery.isLiveTracked {
                    if let eta = etaText {
                        infoRow(icon: "clock.badge.checkmark", label: "Estimated delivery", value: eta)
                    }
                    if let last = lastUpdateText {
                        infoRow(icon: "arrow.triangle.2.circlepath", label: "Last update", value: last)
                    }
                    if delivery.liveCheckpoints.isEmpty {
                        Text("Waiting for the courier's first scan…")
                            .font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor)
                    }
                } else {
                    Text(delivery.trackingNumber?.isEmpty == false
                         ? "Live tracking is starting — check back shortly."
                         : "Add a tracking number to follow this parcel live.")
                        .font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor)
                }
            }
        }
    }

    private func infoRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor).frame(width: 20)
            Text(label).font(AppFont.subheadline).foregroundStyle(.primary)
            Spacer()
            Text(value).font(AppFont.subheadline).foregroundStyle(Color.secondaryTextColor)
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineCard: some View {
        let events = delivery.liveCheckpoints
        if !events.isEmpty {
            GlassCard(padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tracking history")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.bottom, AppSpacing.md)

                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, cp in
                        TimelineRow(
                            checkpoint: cp,
                            isFirst: idx == 0,
                            isLast: idx == events.count - 1,
                            tint: idx == 0 ? delivery.statusColor : Color.secondaryTextColor
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: AppSpacing.sm) {
            if delivery.isActive {
                GlassWideButton(icon: "checkmark.circle.fill", label: "Mark as delivered") {
                    HapticFeedback.success()
                    Task { await deliveryService.markDelivered(delivery) }
                }
            }
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await deliveryService.delete(delivery); dismiss() }
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(AppFont.subheadline).foregroundStyle(Color.brandDanger)
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                    .background(Color.brandDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func refresh() async {
        await deliveryService.reload()
    }

    private var liveStatusLabel: String {
        guard let s = delivery.liveStatus else { return delivery.statusLabel }
        switch s {
        case "pending":              return String(localized: "Pending")
        case "info_received":        return String(localized: "Info received")
        case "in_transit":           return String(localized: "In transit")
        case "out_for_delivery":     return String(localized: "Out for delivery")
        case "available_for_pickup": return String(localized: "Ready for pickup")
        case "delivered":            return String(localized: "Delivered")
        case "failed_attempt":       return String(localized: "Failed attempt")
        case "exception":            return String(localized: "Exception")
        case "expired":              return String(localized: "Expired")
        default:                     return delivery.statusLabel
        }
    }

    private var etaText: String? {
        guard let eta = delivery.estimatedDelivery, let d = ISODate.date(from: eta) else {
            return delivery.expectedDisplay
        }
        let f = DateFormatter(); f.dateFormat = "d MMM"
        if Calendar.current.isDateInToday(d) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(d) { return String(localized: "Tomorrow") }
        return f.string(from: d)
    }

    private var lastUpdateText: String? {
        guard let ts = delivery.lastEventAt, let d = ISODate.date(from: ts) else { return nil }
        let f = DateFormatter(); f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Timeline row (dot + connecting rail + event)

private struct TimelineRow: View {
    let checkpoint: TrackingCheckpoint
    let isFirst: Bool
    let isLast: Bool
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(tint)
                    .frame(width: isFirst ? 12 : 9, height: isFirst ? 12 : 9)
                    .overlay(
                        Circle().stroke(tint.opacity(0.25), lineWidth: isFirst ? 4 : 0)
                    )
                    .padding(.top, 3)
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(AppOpacity.hairline))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.message?.isEmpty == false ? checkpoint.message! : (checkpoint.status ?? ""))
                    .font(AppFont.scaled(14, weight: isFirst ? .semibold : .regular))
                    .foregroundStyle(isFirst ? .primary : Color.secondaryTextColor)
                if let loc = checkpoint.location, !loc.isEmpty {
                    Text(loc).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                if let t = timeText {
                    Text(t).font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
            }
            .padding(.bottom, isLast ? 0 : AppSpacing.base)
            Spacer(minLength: 0)
        }
    }

    private var timeText: String? {
        guard let d = checkpoint.date else { return checkpoint.time }
        let f = DateFormatter(); f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }
}
