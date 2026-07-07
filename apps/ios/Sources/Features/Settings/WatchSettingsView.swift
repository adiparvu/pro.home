import SwiftUI

// MARK: - Apple Watch hub
//
// One page that owns the whole wrist experience from the phone: a live
// preview of the watch with the owner's pages in the owner's order, the
// page personalization itself, the sync link (paired / installed / last
// delivery, with a manual push), what data actually rides each payload,
// and the Siri phrases the wrist understands. Choices persist in the App
// Group and ride the very next payload push, so the watch rearranges
// itself within seconds — no watch-side settings screen to maintain.
// Today is the anchor: always first, never hideable, because it is the
// page every other page reports into.

struct WatchSettingsView: View {
    private struct PageItem: Identifiable, Equatable {
        let key: String
        var enabled: Bool
        var id: String { key }
    }

    @State private var items: [PageItem] = []
    @State private var link: WatchSyncService.LinkStatus?
    @State private var lastPush: Date?
    @State private var payload: WatchPayload?

    private static let meta: [String: (icon: String, color: Color, label: LocalizedStringKey)] = [
        "tasks":      ("checklist", .teal, "watch_tasks"),
        "plants":     ("leaf.fill", Color(red: 0.15, green: 0.80, blue: 0.40), "watch_plants"),
        "shopping":   ("cart.fill", Color.brandSkyBlue, "watch_shopping"),
        "pantry":     ("basket.fill", .orange, "watch_pantry"),
        "deliveries": ("shippingbox.fill", .indigo, "watch_deliveries"),
        "map":        ("map.fill", .purple, "watch_map"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(titleKey: "watch_settings_title",
                       subtitleKey: "watch_settings_subtitle")

            List {
                previewSection
                syncSection
                todaySection
                pagesSection
                dataSection
                siriSection
                complicationsSection
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: items) { old, _ in
            // The initial load also lands here — only user edits persist.
            guard !old.isEmpty else { return }
            save()
        }
    }

    // MARK: Live preview — the wrist as it will actually look

    /// Today plus the enabled pages, in the chosen order.
    private var previewKeys: [String] {
        ["today"] + items.filter(\.enabled).map(\.key)
    }

    private var previewSection: some View {
        Section {
            HStack {
                Spacer()
                watchMock
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// A miniature watch: the case is a bespoke illustration, so its
    /// geometry is intentionally literal rather than token-driven.
    private var watchMock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.30), lineWidth: 3)
                )
            VStack(alignment: .leading, spacing: 4) {
                ForEach(previewKeys, id: \.self) { key in
                    previewChip(key)
                }
            }
            .padding(.horizontal, AppSpacing.md)
        }
        .frame(width: 150, height: 186)
        .overlay(alignment: .trailing) {
            // Digital crown + side button.
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.30))
                    .frame(width: 4, height: 26)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.22))
                    .frame(width: 3, height: 18)
            }
            .offset(x: 6)
        }
        .animation(.snappy(duration: 0.3), value: previewKeys)
        .accessibilityHidden(true)
    }

    private func previewChip(_ key: String) -> some View {
        let icon = key == "today" ? "house.fill" : (Self.meta[key]?.icon ?? "circle")
        let color: Color = key == "today" ? .blue : (Self.meta[key]?.color ?? .gray)
        let label: LocalizedStringKey = key == "today" ? "watch_page_today"
                                                       : (Self.meta[key]?.label ?? "")
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    // MARK: Sync link

    private var syncSection: some View {
        Section {
            if let link, link.paired {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "applewatch", color: .blue)
                    Text("watch_sync_paired")
                        .font(.system(size: 15))
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandSuccess)
                }
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "square.and.arrow.down.on.square", color: .indigo)
                    Text(link.installed ? "watch_sync_installed" : "watch_sync_not_installed")
                        .font(.system(size: 15))
                    Spacer()
                    Image(systemName: link.installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(link.installed ? Color.brandSuccess : Color.brandWarning)
                }
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "arrow.triangle.2.circlepath", color: .teal)
                    Text("watch_sync_last_push")
                        .font(.system(size: 15))
                    Spacer()
                    if let lastPush {
                        Text(lastPush, style: .relative)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("watch_sync_never")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if link.installed {
                    Button {
                        HapticFeedback.success()
                        syncNow()
                    } label: {
                        HStack(spacing: 12) {
                            ColoredIconBadge(icon: "arrow.up.applewatch", color: .green)
                            Text("watch_sync_now")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "applewatch.slash", color: .gray)
                    Text("watch_sync_not_paired")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("watch_sync_header")
        }
    }

    // MARK: Pages (Today locked, the rest reorderable + toggleable)

    private var todaySection: some View {
        Section {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "house.fill", color: .blue)
                Text("watch_page_today")
                    .font(.system(size: 15))
                Spacer()
                Image(systemName: "lock.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        } footer: {
            Text("watch_today_footer")
        }
    }

    private var pagesSection: some View {
        Section {
            ForEach($items) { $item in
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: Self.meta[item.key]?.icon ?? "circle",
                                     color: Self.meta[item.key]?.color ?? .gray)
                    Text(Self.meta[item.key]?.label ?? "")
                        .font(.system(size: 15))
                    Spacer()
                    Toggle("", isOn: $item.enabled)
                        .labelsHidden()
                }
            }
            .onMove { from, to in
                items.move(fromOffsets: from, toOffset: to)
            }
        } header: {
            Text("watch_pages_header")
        } footer: {
            Text("watch_pages_footer")
        }
    }

    // MARK: What actually rides the payload

    private var dataSection: some View {
        Section {
            if let payload {
                dataRow("checklist", .teal, "watch_tasks",
                        count: payload.tasks.filter { !$0.isCompleted }.count)
                dataRow("leaf.fill", Color(red: 0.15, green: 0.80, blue: 0.40), "watch_plants",
                        count: payload.plants.filter(\.needsWatering).count)
                dataRow("cart.fill", Color.brandSkyBlue, "watch_shopping",
                        count: payload.supplies.filter { !$0.isCompleted }.count)
                dataRow("basket.fill", .orange, "watch_pantry", count: payload.pantry.count)
                dataRow("shippingbox.fill", .indigo, "watch_deliveries", count: payload.deliveries.count)
                dataRow("cloud.sun.fill", .cyan, "watch_data_weather",
                        present: payload.weatherTemp != nil)
                dataRow("chart.pie.fill", .pink, "watch_data_budget",
                        present: payload.budgetSpent != nil)
                dataRow("flame.fill", .orange, "watch_data_streak",
                        count: payload.streakDays ?? 0)
            }
        } header: {
            Text("watch_data_header")
        } footer: {
            Text("watch_data_footer")
        }
    }

    private func dataRow(_ icon: String, _ color: Color, _ label: LocalizedStringKey,
                         count: Int) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
            Spacer()
            Text("\(count)")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func dataRow(_ icon: String, _ color: Color, _ label: LocalizedStringKey,
                         present: Bool) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
            Spacer()
            Image(systemName: present ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(present ? Color.brandSuccess : Color.secondary)
        }
    }

    // MARK: Siri on the wrist

    private var siriSection: some View {
        Section {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "checkmark.circle.fill", color: .teal)
                Text("watch_siri_complete_task")
                    .font(.system(size: 15))
            }
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "drop.fill", color: .blue)
                Text("watch_siri_water")
                    .font(.system(size: 15))
            }
        } header: {
            Text("watch_siri_header")
        } footer: {
            Text("watch_siri_footer")
        }
    }

    private var complicationsSection: some View {
        Section {
        } footer: {
            Text("watch_complications_footer")
        }
    }

    // MARK: Load / save

    private func load() {
        link = WatchSyncService.shared.linkStatus
        lastPush = WatchSyncService.shared.lastPushAt
        payload = SharedDataStore.currentWatchPayload()
        guard items.isEmpty else { return }
        let prefs = SharedDataStore.readWatchPagePrefs()
        items = prefs.order.map { PageItem(key: $0, enabled: !prefs.hidden.contains($0)) }
    }

    /// Persist and push in the same breath — the wrist reorders in seconds,
    /// not on the next app launch.
    private func save() {
        guard !items.isEmpty else { return }
        SharedDataStore.writeWatchPagePrefs(
            order: items.map(\.key),
            hidden: items.filter { !$0.enabled }.map(\.key))
        syncNow()
    }

    private func syncNow() {
        if let payload = SharedDataStore.currentWatchPayload() {
            WatchSyncService.shared.push(payload)
        }
        lastPush = WatchSyncService.shared.lastPushAt ?? Date()
    }
}
