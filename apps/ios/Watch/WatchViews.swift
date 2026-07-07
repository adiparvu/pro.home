import SwiftUI

// MARK: - Pages

enum WatchPage: Hashable {
    case today, tasks, plants, shopping, deliveries
}

// MARK: - Root: vertical pages, or the sync prompt
//
// Today is the glance; Tasks/Plants/Shopping act (tap the leading symbol for
// the instant action, tap the row for a detail page — the Reminders-on-watch
// split); Deliveries reads the live parcels. Content-driven paging keeps the
// crown from scrolling through empty screens, and every complication
// deep-links straight to its page through prvio:// URLs.

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var selection: WatchPage = .today

    var body: some View {
        if let payload = store.payload {
            TabView(selection: $selection) {
                TodayGlance(payload: payload, selection: $selection)
                    .tag(WatchPage.today)
                TasksPage(tasks: payload.tasks)
                    .tag(WatchPage.tasks)
                PlantsPage(plants: payload.plants)
                    .tag(WatchPage.plants)
                if payload.supplies.contains(where: { !$0.isCompleted }) {
                    ShoppingPage(supplies: payload.supplies)
                        .tag(WatchPage.shopping)
                }
                if !payload.deliveries.isEmpty {
                    DeliveriesPage(deliveries: payload.deliveries)
                        .tag(WatchPage.deliveries)
                }
            }
            .tabViewStyle(.verticalPage)
            .onOpenURL { url in
                // Complication taps: prvio://tasks, prvio://plants, …
                switch url.host {
                case "tasks":                  selection = .tasks
                case "plants":                 selection = .plants
                case "shopping", "supplies":   selection = .shopping
                case "deliveries", "packages": selection = .deliveries
                default:                       selection = .today
                }
            }
        } else {
            waiting
        }
    }

    private var waiting: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_waiting_title")
                .font(.headline)
            Text("watch_waiting_msg")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Page 1: Today

private struct TodayGlance: View {
    let payload: WatchPayload
    @Binding var selection: WatchPage

    private var snapshot: PRVIOWidgetSnapshot { payload.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        statCell(count: snapshot.openTaskCount, label: "watch_open",
                                 icon: "checklist", urgent: snapshot.overdueTaskCount > 0,
                                 page: .tasks)
                        statCell(count: snapshot.plantsNeedingWater, label: "watch_water",
                                 icon: "drop.fill", urgent: false, page: .plants)
                        statCell(count: snapshot.activeDeliveryCount, label: "watch_deliveries",
                                 icon: "shippingbox.fill", urgent: false, page: .deliveries)
                        statCell(count: snapshot.pendingSupplyCount, label: "watch_shopping",
                                 icon: "cart.fill", urgent: false, page: .shopping)
                    }

                    if snapshot.unreadMessages > 0 {
                        unreadRow(snapshot.unreadMessages)
                    }

                    if let critical = snapshot.criticalTaskTitle {
                        urgentRow(critical)
                    } else if let next = snapshot.nextMaintenanceTitle {
                        nextRow(next, due: snapshot.nextMaintenanceDue)
                    }
                }
            }
            .navigationTitle(Text(verbatim: "PRVIO"))
            .containerBackground(Color.blue.gradient.opacity(0.25), for: .navigation)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.propertyName ?? "PRVIO")
                .font(.headline)
                .lineLimit(1)
            if let score = snapshot.propertyHealthScore {
                HStack(spacing: 5) {
                    Gauge(value: Double(score), in: 0...100) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .frame(width: 54)
                    Text(verbatim: "\(score)%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("watch_health"))
            }
        }
    }

    // A glance cell that is also a shortcut: tapping crowns straight to the
    // page it counts.
    private func statCell(count: Int, label: LocalizedStringKey, icon: String,
                          urgent: Bool, page: WatchPage) -> some View {
        Button {
            selection = page
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    if urgent {
                        Circle().fill(.red).frame(width: 6, height: 6)
                    }
                }
                Text(verbatim: "\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func unreadRow(_ count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "message.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
            Text(verbatim: "\(count)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("watch_unread")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private func urgentRow(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(title)
                .font(.footnote)
                .lineLimit(2)
        }
        .padding(.top, 2)
    }

    private func nextRow(_ title: String, due: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.footnote)
                .lineLimit(2)
            if let due {
                Text(due)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Page 2: Tasks

private struct TasksPage: View {
    let tasks: [TaskCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var open: [TaskCatalogEntry] {
        // Overdue first, then the rest, capped for wrist reading.
        let pending = tasks.filter { !$0.isCompleted }
        return Array((pending.filter { $0.isOverdue == true }
                      + pending.filter { $0.isOverdue != true }).prefix(12))
    }

    var body: some View {
        NavigationStack {
            Group {
                if open.isEmpty {
                    AllClearView(icon: "checkmark.circle")
                } else {
                    List(open, id: \.id) { task in
                        // The circle completes on the spot; the row opens the
                        // detail — the Reminders split, no accidental completes.
                        NavigationLink(value: task.id) {
                            HStack(spacing: 8) {
                                Button {
                                    withAnimation(.snappy) { store.completeTask(task.id) }
                                } label: {
                                    Image(systemName: "circle")
                                        .font(.system(size: 17, weight: .light))
                                        .foregroundStyle(task.isOverdue == true ? Color.red : Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("watch_complete"))

                                Text(task.title)
                                    .font(.footnote)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let task = open.first(where: { $0.id == id }) {
                            TaskDetail(task: task)
                        }
                    }
                }
            }
            .navigationTitle(Text("watch_tasks"))
            .containerBackground(Color.blue.gradient.opacity(0.3), for: .navigation)
        }
    }
}

private struct TaskDetail: View {
    let task: TaskCatalogEntry
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if task.isOverdue == true {
                    Label { Text("watch_overdue") } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                }

                Text(task.title)
                    .font(.headline)

                Button {
                    store.completeTask(task.id)
                    dismiss()
                } label: {
                    Label { Text("watch_complete") } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(Color.blue.gradient.opacity(0.3), for: .navigation)
    }
}

// MARK: - Page 3: Plants

private struct PlantsPage: View {
    let plants: [PlantCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var thirsty: [PlantCatalogEntry] { plants.filter(\.needsWatering) }

    var body: some View {
        NavigationStack {
            Group {
                if thirsty.isEmpty {
                    AllClearView(icon: "leaf")
                } else {
                    List(thirsty, id: \.id) { plant in
                        NavigationLink(value: plant.id) {
                            HStack(spacing: 6) {
                                Button {
                                    withAnimation(.snappy) { store.waterPlant(plant.id) }
                                } label: {
                                    Image(systemName: "drop.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("watch_water_now"))

                                Text(plant.emoji)
                                Text(plant.name)
                                    .font(.footnote)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let plant = thirsty.first(where: { $0.id == id }) {
                            PlantDetail(plant: plant)
                        }
                    }
                }
            }
            .navigationTitle(Text("watch_plants"))
            .containerBackground(Color.green.gradient.opacity(0.3), for: .navigation)
        }
    }
}

private struct PlantDetail: View {
    let plant: PlantCatalogEntry
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(plant.emoji)
                    .font(.system(size: 44))
                Text(plant.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Button {
                    store.waterPlant(plant.id)
                    dismiss()
                } label: {
                    Label { Text("watch_water_now") } icon: {
                        Image(systemName: "drop.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(Color.green.gradient.opacity(0.3), for: .navigation)
    }
}

// MARK: - Page 4: Shopping (tap to check off)

private struct ShoppingPage: View {
    let supplies: [SupplyCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var pending: [SupplyCatalogEntry] {
        Array(supplies.filter { !$0.isCompleted }.prefix(15))
    }

    var body: some View {
        NavigationStack {
            Group {
                if pending.isEmpty {
                    AllClearView(icon: "cart")
                } else {
                    List(pending, id: \.id) { item in
                        Button {
                            withAnimation(.snappy) { store.checkSupply(item.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.system(size: 17, weight: .light))
                                    .foregroundStyle(.secondary)
                                Text(item.name)
                                    .font(.footnote)
                                    .lineLimit(2)
                            }
                        }
                        .accessibilityHint(Text("watch_tap_check"))
                    }
                }
            }
            .navigationTitle(Text("watch_shopping"))
            .containerBackground(Color.orange.gradient.opacity(0.3), for: .navigation)
        }
    }
}

// MARK: - Page 5: Deliveries (glanceable, read-only)

private struct DeliveriesPage: View {
    let deliveries: [DeliveryCatalogEntry]

    var body: some View {
        NavigationStack {
            List(deliveries.prefix(10), id: \.id) { parcel in
                NavigationLink(value: parcel.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: DeliveryGlyphs.icon(for: parcel.status))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(parcel.status == "out_for_delivery" ? .orange : .secondary)
                            Text(parcel.title)
                                .font(.footnote)
                                .lineLimit(2)
                        }
                        DeliveryGlyphs.statusLabel(for: parcel.status)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let parcel = deliveries.first(where: { $0.id == id }) {
                    DeliveryDetail(parcel: parcel)
                }
            }
            .navigationTitle(Text("watch_deliveries"))
            .containerBackground(Color.cyan.gradient.opacity(0.3), for: .navigation)
        }
    }
}

private struct DeliveryDetail: View {
    let parcel: DeliveryCatalogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: DeliveryGlyphs.icon(for: parcel.status))
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(parcel.status == "out_for_delivery" ? .orange : .secondary)

                Text(parcel.title)
                    .font(.headline)

                DeliveryGlyphs.statusLabel(for: parcel.status)
                    .font(.footnote.weight(.semibold))

                if let carrier = parcel.carrier, !carrier.isEmpty {
                    Text(verbatim: carrier)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let eta = parcel.eta, !eta.isEmpty {
                    Text(verbatim: eta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(Color.cyan.gradient.opacity(0.3), for: .navigation)
    }
}

// MARK: - Delivery glyphs (shared row/detail vocabulary)

enum DeliveryGlyphs {
    static func icon(for status: String) -> String {
        switch status {
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        default:                 return "shippingbox.fill"
        }
    }

    // The same keys the iPhone's Delivery.statusLabel resolves.
    static func statusLabel(for status: String) -> Text {
        switch status {
        case "expected":         return Text("Expected")
        case "out_for_delivery": return Text("Out for delivery")
        case "delivered":        return Text("Delivered")
        case "missed":           return Text("Missed")
        case "returned":         return Text("Returned")
        default:                 return Text(verbatim: status)
        }
    }
}

// MARK: - Shared empty state

private struct AllClearView: View {
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_all_good")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
