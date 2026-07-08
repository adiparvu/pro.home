import SwiftUI
import RoomPlan

// MARK: - Room inspector (Plans & 3D rebuild, phase D)
//
// Tap a room — on the plan or in the list — and see everything the house
// knows about it: the matching Digital Twin zone's health, the inventory
// stored there and the appliances installed there (both matched by their
// existing `location` text against the room's name, the same transparent
// name convention the health tint uses), plus the scan actions.

struct RoomInspectorSheet: View {
    let room: RoomRecord
    /// Digital Twin health when a zone shares the room's name.
    let health: Int?
    let onViewScan: () -> Void
    let onScan: () -> Void

    @Environment(InventoryService.self) private var inventoryService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(\.dismiss) private var dismiss

    private func matches(_ location: String?) -> Bool {
        guard let location, !location.isEmpty else { return false }
        return location.compare(room.name,
                                options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    var body: some View {
        let items = inventoryService.items.filter { matches($0.location) }
        let appliances = applianceService.appliances.filter { matches($0.location) }

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    scanCard
                    if let health {
                        healthCard(health)
                    }
                    if !appliances.isEmpty {
                        listCard(titleKey: "room_appliances %lld", count: appliances.count) {
                            ForEach(appliances) { appliance in
                                inspectorRow(icon: "washer.fill", tint: .cyan,
                                             title: appliance.name,
                                             subtitle: appliance.brand)
                            }
                        }
                    }
                    if !items.isEmpty {
                        listCard(titleKey: "room_inventory %lld", count: items.count) {
                            ForEach(items) { item in
                                inspectorRow(icon: item.categoryIcon, tint: item.categoryColor,
                                             title: item.name,
                                             subtitle: item.brand.isEmpty ? nil : item.brand)
                            }
                        }
                    }
                    if items.isEmpty && appliances.isEmpty {
                        Text("room_inspector_empty")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.top, AppSpacing.md)
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.footnoteEmphasis)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(RoomKind.color(room.roomType).opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: room.kindIcon)
                    .font(AppFont.title3)
                    .foregroundStyle(RoomKind.color(room.roomType))
            }
            Text(room.name)
                .font(AppFont.title3)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text(room.kindLabel)
                if let area = room.areaSqm, area > 0 {
                    Text("·")
                    Text(String(format: String(localized: "room_area_fmt %@"),
                                String(format: "%.0f", area)))
                }
            }
            .font(AppFont.caption)
            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
        }
    }

    // MARK: Cards

    private var scanCard: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(.purple)
                Text(room.hasScan ? "room_scan_present" : "room_scan_absent")
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                Spacer()
                if room.hasScan {
                    Button {
                        dismiss()
                        onViewScan()
                    } label: {
                        Text("room_view_scan")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.accentColor)
                    }
                } else if RoomCaptureSession.isSupported {
                    Button {
                        dismiss()
                        onScan()
                    } label: {
                        Text("room_scan")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    private func healthCard(_ score: Int) -> some View {
        let tint: Color = score >= 80 ? Color.brandSuccess : score >= 50 ? .orange : Color.brandDanger
        return GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(tint)
                Text("room_health_label")
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(score)%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        }
    }

    private func listCard<Content: View>(titleKey: String, count: Int,
                                         @ViewBuilder content: () -> Content) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(format: String(localized: String.LocalizationValue(titleKey)), count))
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .textCase(.uppercase)
                    .kerning(0.5)
                content()
            }
        }
    }

    private func inspectorRow(icon: String, tint: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(AppFont.caption)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }
}
