import SwiftUI

// MARK: - Energy card (Spaces tab)
//
// The compact daily-energy glass card between the quick row and the mode
// toggle: today's kWh (one decimal), a delta arrow against yesterday, and —
// ONLY when power-integration contributed — an explicit "≈ estimated from
// N readings" caption, so an estimate never masquerades as a measurement.
// Tapping opens the detail sheet (today vs yesterday, production line,
// per-zone bars). Renders nothing when the installation has no power or
// energy sensors — the card never invents a dashboard.

struct EnergyCard: View {
    private let store = EnergyStore.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var showDetail = false

    var body: some View {
        if store.hasEnergySensors {
            card
        }
    }

    private var card: some View {
        Button {
            HapticFeedback.impact(.light)
            showDetail = true
        } label: {
            cardLabel
        }
        .buttonStyle(SmartCardPressStyle())
        .sheet(isPresented: $showDetail) {
            EnergyDetailSheet(store: store)
        }
        .task { await store.refreshIfStale() }
        // Foreground returns re-ask; the store's 15-minute staleness gate
        // makes the extra calls free.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshIfStale() }
        }
    }

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "bolt.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.brandGold)
                Text("energy_card_title")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                deltaArrow
            }
            valueRow
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueRow: some View {
        if let today = store.today {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                    Text(verbatim: EnergyFormat.number(today.kWh))
                        .font(AppFont.title2)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(verbatim: "kWh")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                }
                if today.isEstimate {
                    Text("energy_estimate_caption \(today.sampleCount)")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            // No readings in the window yet — say so, never a claimed 0.0.
            Text("energy_card_no_data")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Green down-arrow when today is below yesterday, warning up-arrow when
    /// above — shown only when BOTH days actually hold data.
    @ViewBuilder
    private var deltaArrow: some View {
        if let today = store.today, let yesterday = store.yesterday,
           today.kWh != yesterday.kWh {
            let isDown = today.kWh < yesterday.kWh
            Image(systemName: isDown ? "arrow.down" : "arrow.up")
                .font(AppFont.captionStrong)
                .foregroundStyle(isDown ? Color.brandSuccess : Color.brandWarning)
                .accessibilityLabel(isDown
                                    ? Text("energy_delta_down_a11y")
                                    : Text("energy_delta_up_a11y"))
        }
    }
}

// MARK: - Detail sheet

struct EnergyDetailSheet: View {
    var store: EnergyStore = .shared

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    header
                    daysCard
                    if !store.perZone.isEmpty { zonesCard }
                    footer
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header (SensorHistorySheet conventions)

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    HapticFeedback.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .accessibilityLabel(Text("sh_close"))
                Spacer(minLength: 0)
            }
            Text("energy_card_title")
                .font(AppFont.scaled(26, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: Today / yesterday / production

    private var daysCard: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                figureRow(titleKey: "energy_today", figure: store.today, emphasized: true)
                figureRow(titleKey: "energy_yesterday", figure: store.yesterday)
                if let produced = store.producedToday {
                    HStack(alignment: .firstTextBaseline) {
                        Text("energy_produced_today")
                            .font(AppFont.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(verbatim: EnergyFormat.kWh(produced))
                            .font(AppFont.footnoteEmphasis)
                            .monospacedDigit()
                            .foregroundStyle(Color.brandSuccess)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let today = store.today, today.isEstimate {
                    Text("energy_estimate_caption \(today.sampleCount)")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func figureRow(titleKey: LocalizedStringKey,
                           figure: EnergyFigure?,
                           emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titleKey)
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            // A missing day is an honest dash, never a fabricated zero.
            Text(verbatim: figure.map { EnergyFormat.kWh($0.kWh) } ?? "—")
                .font(emphasized ? AppFont.headline : AppFont.footnoteEmphasis)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Per-zone bars

    private var zonesCard: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("energy_zones_title")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                let zones = store.perZone
                let maxKWh = zones.map { $0.kWh }.max() ?? 0
                // Tuple elements have no key paths — iterate by index; the
                // list is tiny and rebuilt whole on every refresh.
                ForEach(zones.indices, id: \.self) { index in
                    zoneRow(zone: zones[index].zone,
                            kWh: zones[index].kWh,
                            maxKWh: maxKWh)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func zoneRow(zone: String, kWh: Double, maxKWh: Double) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: zone)
                    .font(AppFont.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.sm)
                Text(verbatim: EnergyFormat.kWh(kWh))
                    .font(AppFont.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.subtleFill)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: maxKWh > 0
                               ? proxy.size.width * kWh / maxKWh
                               : 0)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer — where the figures come from

    private var footer: some View {
        Text("energy_footer_scope")
            .font(AppFont.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Formatting

/// "12,4" / "12,4 kWh" — locale-aware, exactly one decimal (the card's
/// reading style; a false extra precision would overstate the estimate).
private enum EnergyFormat {
    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    static func kWh(_ value: Double) -> String {
        "\(number(value)) kWh"
    }
}
