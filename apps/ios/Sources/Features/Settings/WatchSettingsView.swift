import SwiftUI
import UniformTypeIdentifiers

// MARK: - Apple Watch hub
//
// One fluid scroll that owns the whole wrist experience from the phone,
// hero-first: a live, auto-cycling preview of the watch rendering the REAL
// App Group data (the same snapshot + catalogs every payload push carries),
// a single connection pill for the phone↔watch link, large drag-to-reorder
// page cards, one honest line about what rides the payload, a quiet role-
// scope note, and the Siri/complications manual condensed at the bottom.
// Choices persist in the App Group and ride the very next payload push, so
// the watch rearranges itself within seconds — no watch-side settings
// screen to maintain. Today is the anchor: always first, never hideable,
// because it is the page every other page reports into.

struct WatchSettingsView: View {
    fileprivate struct PageItem: Identifiable, Equatable {
        let key: String
        var enabled: Bool
        var id: String { key }
    }

    @Environment(PropertyService.self) private var propertyService

    @State private var items: [PageItem] = []
    @State private var link: WatchSyncService.LinkStatus?
    @State private var lastPush: Date?
    @State private var payload: WatchPayload?
    /// The page key currently lifted by a reorder drag.
    @State private var draggingKey: String?

    private static let meta: [String: (icon: String, label: LocalizedStringKey,
                                       description: LocalizedStringKey)] = [
        "tasks":      ("checklist",         "watch_tasks",      "watch_page_desc_tasks"),
        "plants":     ("leaf.fill",         "watch_plants",     "watch_page_desc_plants"),
        "shopping":   ("cart.fill",         "watch_shopping",   "watch_page_desc_shopping"),
        "pantry":     ("basket.fill",       "watch_pantry",     "watch_page_desc_pantry"),
        "deliveries": ("shippingbox.fill",  "watch_deliveries", "watch_page_desc_deliveries"),
        "map":        ("map.fill",          "watch_map",        "watch_page_desc_map"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                heroSection
                connectionPill
                pagesSection
                if let payload {
                    payloadSection(payload)
                }
                scopeRow
                siriSection
                crashReportSection
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xxl)
            // Catch-all: a reorder drag released between cards still lands
            // here, so the lifted card never stays dimmed after a miss.
            .onDrop(of: [.text], delegate: DragResetDelegate(draggingKey: $draggingKey))
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("watch_settings_title")
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: load)
        .onChange(of: items) { old, _ in
            // The initial load also lands here — only user edits persist.
            guard !old.isEmpty else { return }
            save()
        }
    }

    // MARK: Wrist black box — the last captured watch crash, if any
    //
    // Filled by WatchSyncService when the wrist forwards a report captured
    // by WatchCrashRecorder ("opens for a second and closes"). Honest and
    // quiet: the section only exists while a report exists; Copy puts the
    // full text on the pasteboard so it can be pasted straight into a chat.

    @ViewBuilder private var crashReportSection: some View {
        if let report = UserDefaults.standard.string(forKey: "prvio.watch.crashReport") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("watch_crash_title")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.red)
                Text(verbatim: report)
                    .font(AppFont.scaled(11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                Button {
                    UIPasteboard.general.string = report
                    HapticFeedback.success()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(AppFont.footnoteEmphasis)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    // MARK: Hero — the wrist as it looks right now

    /// The pages the wrist would actually render, mirroring the watch's own
    /// gating: shopping hides when nothing is pending, pantry/deliveries hide
    /// when empty, map hides without coordinates — and an outsider's watch
    /// keeps to Today + their tasks, exactly like the payload it receives.
    private var heroPageKeys: [String] {
        guard let payload else { return [] }
        guard payload.isFamilyScope else { return ["today", "tasks"] }
        var keys = ["today"]
        for item in items where item.enabled {
            switch item.key {
            case "shopping":
                if payload.supplies.contains(where: { !$0.isCompleted }) { keys.append(item.key) }
            case "pantry":
                if !payload.pantry.isEmpty { keys.append(item.key) }
            case "deliveries":
                if !payload.deliveries.isEmpty { keys.append(item.key) }
            case "map":
                if payload.latitude != nil, payload.longitude != nil { keys.append(item.key) }
            default:
                keys.append(item.key)   // tasks & plants always render on the wrist
            }
        }
        return keys
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("watch_hero_title")
            WatchSettingsHero(payload: payload, pageKeys: heroPageKeys)
        }
    }

    // MARK: Connection — one pill for the whole link

    private var linkHealthy: Bool {
        (link?.paired ?? false) && (link?.installed ?? false)
    }

    private var connectionPill: some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(linkHealthy ? Color.brandSuccess : Color.primary.opacity(AppOpacity.disabled))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                connectionTitle
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if linkHealthy {
                    connectionSubtitle
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            if linkHealthy {
                Button {
                    HapticFeedback.success()
                    syncNow()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.applewatch")
                            .font(AppFont.scaled(12, weight: .semibold))
                        Text("watch_sync_action")
                            .font(AppFont.captionEmphasis)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 7)
                    .glassFilterCapsule(selected: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("watch_sync_now")
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .glassCapsule()
        .accessibilityElement(children: .combine)
    }

    private var connectionTitle: Text {
        if let link, link.paired {
            return link.installed ? Text("watch_sync_paired") : Text("watch_sync_not_installed")
        }
        return Text("watch_sync_not_paired")
    }

    private var connectionSubtitle: Text {
        if let lastPush {
            return Text("watch_synced_ago \(lastPush, format: .relative(presentation: .named))")
        }
        return Text("watch_sync_last_push") + Text(verbatim: ": ") + Text("watch_sync_never")
    }

    // MARK: Pages — large cards, drag to reorder, Today pinned

    private var pagesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("watch_pages_header")

            todayCard

            ForEach($items) { $item in
                pageCard($item)
            }

            footnote("watch_pages_footer")
        }
    }

    /// Today: always first, never hideable — shown as pinned, not editable.
    private var todayCard: some View {
        HStack(spacing: AppSpacing.md) {
            ColoredIconBadge(icon: "house.fill", color: .blue, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("watch_page_today")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text("watch_today_pinned")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "pin.fill")
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(0.28))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
    }

    private func pageCard(_ item: Binding<PageItem>) -> some View {
        let key = item.wrappedValue.key
        let meta = Self.meta[key]
        return HStack(spacing: AppSpacing.md) {
            ColoredIconBadge(icon: meta?.icon ?? "circle", color: .gray, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta?.label ?? "")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text(meta?.description ?? "")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .opacity(item.wrappedValue.enabled ? 1 : AppOpacity.secondaryText)
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(0.28))
                .accessibilityHidden(true)
            Toggle("", isOn: item.enabled)
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .opacity(draggingKey == key ? 0.55 : 1)
        .onDrag {
            draggingKey = key
            return NSItemProvider(object: key as NSString)
        }
        .onDrop(of: [.text], delegate: PageDropDelegate(key: key, items: $items,
                                                        draggingKey: $draggingKey))
        .accessibilityElement(children: .combine)
        // VoiceOver can't drag — expose the reorder as custom actions.
        .accessibilityAction(named: Text("watch_move_up")) { move(key, by: -1) }
        .accessibilityAction(named: Text("watch_move_down")) { move(key, by: +1) }
    }

    private func move(_ key: String, by delta: Int) {
        guard let from = items.firstIndex(where: { $0.key == key }) else { return }
        let to = from + delta
        guard items.indices.contains(to) else { return }
        HapticFeedback.impact(.light)
        withAnimation(.snappy(duration: 0.25)) {
            items.swapAt(from, to)
        }
    }

    /// Reorders live while the drag hovers over a sibling card — the same
    /// feel as List's reorder, with a haptic per displacement. Persistence
    /// rides the existing items onChange → save() path.
    private struct PageDropDelegate: DropDelegate {
        let key: String
        @Binding var items: [PageItem]
        @Binding var draggingKey: String?

        func dropEntered(info: DropInfo) {
            guard let draggingKey, draggingKey != key,
                  let from = items.firstIndex(where: { $0.key == draggingKey }),
                  let to = items.firstIndex(where: { $0.key == key }) else { return }
            HapticFeedback.impact(.light)
            withAnimation(.snappy(duration: 0.25)) {
                items.move(fromOffsets: IndexSet(integer: from),
                           toOffset: to > from ? to + 1 : to)
            }
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingKey = nil
            return true
        }
    }

    /// Clears the drag highlight when a reorder drag ends anywhere else on
    /// the page (between cards, over the hero, …).
    private struct DragResetDelegate: DropDelegate {
        @Binding var draggingKey: String?

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingKey = nil
            return true
        }
    }

    // MARK: What actually rides the payload — one honest line

    private func payloadSection(_ payload: WatchPayload) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("watch_data_header")

            HStack(spacing: AppSpacing.md) {
                ColoredIconBadge(icon: "arrow.up.applewatch", color: .teal, size: 38)
                (Text("watch_payload_tasks \(payload.tasks.count)")
                    + Text(verbatim: " · ")
                    + Text("watch_payload_plants \(payload.plants.count)")
                    + Text(verbatim: " · ")
                    + Text("watch_payload_sensors \(payload.sensors.count)"))
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .liquidGlass(cornerRadius: AppRadius.xl)
            .accessibilityElement(children: .combine)

            footnote("watch_data_footer")
        }
    }

    // MARK: Role scope — what this wrist is allowed to see

    private var scopeRow: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: propertyService.isFamilyMember
                    ? "person.2.fill" : "person.fill.checkmark")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            Text(propertyService.isFamilyMember ? "watch_scope_family" : "watch_scope_personal")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
        .background(Color.subtleFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    // MARK: Siri + complications, condensed

    private var siriSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("watch_siri_header")

            VStack(spacing: 0) {
                siriRow(icon: "checkmark.circle.fill", phrase: "watch_siri_complete_task")
                hairline
                siriRow(icon: "drop.fill", phrase: "watch_siri_water")
                hairline
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    ColoredIconBadge(icon: "applewatch.watchface", color: .purple)
                    Text("watch_complications_footer")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
            }
            .liquidGlass(cornerRadius: AppRadius.xl)

            footnote("watch_siri_footer")
        }
    }

    private func siriRow(icon: String, phrase: LocalizedStringKey) -> some View {
        HStack(spacing: AppSpacing.md) {
            ColoredIconBadge(icon: icon, color: .teal)
            Text(phrase)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 0.4)
            .padding(.leading, 52)
    }

    // MARK: Shared section chrome

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.captionStrong)
            .foregroundStyle(Color.backdropSecondaryText)
            .padding(.leading, AppSpacing.sm)
    }

    private func footnote(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.caption)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.sm)
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
