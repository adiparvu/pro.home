import SwiftUI

// MARK: - Apple Watch page personalization
//
// The wrist should show only what its owner actually uses, in the order they
// reach for it. Choices persist in the App Group and ride the very next
// payload push, so the watch rearranges itself within seconds — no watch-side
// settings screen to maintain. Today is the anchor: always first, never
// hideable, because it is the page every other page reports into.

struct WatchSettingsView: View {
    private struct PageItem: Identifiable, Equatable {
        let key: String
        var enabled: Bool
        var id: String { key }
    }

    @State private var items: [PageItem] = []

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

    private func load() {
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
        if let payload = SharedDataStore.currentWatchPayload() {
            WatchSyncService.shared.push(payload)
        }
    }
}
