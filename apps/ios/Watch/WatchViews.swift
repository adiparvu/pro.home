import SwiftUI

// MARK: - Root: vertical pages, or the sync prompt
//
// Today is the glance; Tasks/Plants/Shopping act on tap (optimistic local
// mutation + queued sync to the phone); Deliveries reads the live parcels.
// Content-driven paging: Shopping and Deliveries only appear when they have
// something to say, so the crown never scrolls through empty screens.

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let payload = store.payload {
            TabView {
                TodayGlance(payload: payload)
                TasksPage(tasks: payload.tasks)
                PlantsPage(plants: payload.plants)
                if payload.supplies.contains(where: { !$0.isCompleted }) {
                    ShoppingPage(supplies: payload.supplies)
                }
                if !payload.deliveries.isEmpty {
                    DeliveriesPage(deliveries: payload.deliveries)
                }
            }
            .tabViewStyle(.verticalPage)
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

    private var snapshot: PRVIOWidgetSnapshot { payload.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    statCell(count: snapshot.openTaskCount, label: "watch_open",
                             icon: "checklist", urgent: snapshot.overdueTaskCount > 0)
                    statCell(count: snapshot.plantsNeedingWater, label: "watch_water",
                             icon: "drop.fill", urgent: false)
                    statCell(count: snapshot.activeDeliveryCount, label: "watch_deliveries",
                             icon: "shippingbox.fill", urgent: false)
                    statCell(count: snapshot.pendingSupplyCount, label: "watch_shopping",
                             icon: "cart.fill", urgent: false)
                }

                if let critical = snapshot.criticalTaskTitle {
                    urgentRow(critical)
                } else if let next = snapshot.nextMaintenanceTitle {
                    nextRow(next, due: snapshot.nextMaintenanceDue)
                }
            }
        }
        .navigationTitle(Text(verbatim: "PRVIO"))
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

    private func statCell(count: Int, label: LocalizedStringKey, icon: String, urgent: Bool) -> some View {
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

// MARK: - Page 2: Tasks (tap the circle to complete)

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
        Group {
            if open.isEmpty {
                AllClearView(icon: "checkmark.circle")
            } else {
                List(open, id: \.id) { task in
                    Button {
                        withAnimation(.snappy) { store.completeTask(task.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(task.isOverdue == true ? Color.red : Color.secondary)
                            Text(task.title)
                                .font(.footnote)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityHint(Text("watch_tap_complete"))
                }
            }
        }
        .navigationTitle(Text("watch_tasks"))
    }
}

// MARK: - Page 3: Plants (tap to water)

private struct PlantsPage: View {
    let plants: [PlantCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var thirsty: [PlantCatalogEntry] { plants.filter(\.needsWatering) }

    var body: some View {
        Group {
            if thirsty.isEmpty {
                AllClearView(icon: "leaf")
            } else {
                List(thirsty, id: \.id) { plant in
                    Button {
                        withAnimation(.snappy) { store.waterPlant(plant.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(plant.emoji)
                            Text(plant.name)
                                .font(.footnote)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "drop.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.blue)
                        }
                    }
                    .accessibilityHint(Text("watch_tap_water"))
                }
            }
        }
        .navigationTitle(Text("watch_plants"))
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
    }
}

// MARK: - Page 5: Deliveries (glanceable, read-only)

private struct DeliveriesPage: View {
    let deliveries: [DeliveryCatalogEntry]

    var body: some View {
        List(deliveries.prefix(10), id: \.id) { parcel in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon(for: parcel.status))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(parcel.status == "out_for_delivery" ? .orange : .secondary)
                    Text(parcel.title)
                        .font(.footnote)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    Text(statusLabel(for: parcel.status))
                    if let carrier = parcel.carrier, !carrier.isEmpty {
                        Text(verbatim: "· \(carrier)")
                    }
                    if let eta = parcel.eta, !eta.isEmpty {
                        Text(verbatim: "· \(eta)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .navigationTitle(Text("watch_deliveries"))
    }

    private func icon(for status: String) -> String {
        switch status {
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        default:                 return "shippingbox.fill"
        }
    }

    // The same keys the iPhone's Delivery.statusLabel resolves.
    private func statusLabel(for status: String) -> Text {
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
