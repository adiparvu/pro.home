import SwiftUI

// MARK: - Root: three vertical pages, or the sync prompt

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let payload = store.payload {
            TabView {
                TodayGlance(payload: payload)
                TasksPage(tasks: payload.tasks)
                PlantsPage(plants: payload.plants)
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
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    private var open: [TaskCatalogEntry] {
        // Overdue first, then the rest, capped for wrist reading.
        let pending = tasks.filter { !$0.isCompleted }
        return Array((pending.filter { $0.isOverdue == true }
                      + pending.filter { $0.isOverdue != true }).prefix(12))
    }

    var body: some View {
        Group {
            if open.isEmpty {
                allClear
            } else {
                List(open, id: \.id) { task in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(task.isOverdue == true ? Color.red : Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                        Text(task.title)
                            .font(.footnote)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle(Text("watch_tasks"))
    }

    private var allClear: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_all_good")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Page 3: Plants

private struct PlantsPage: View {
    let plants: [PlantCatalogEntry]

    private var thirsty: [PlantCatalogEntry] { plants.filter(\.needsWatering) }

    var body: some View {
        Group {
            if thirsty.isEmpty {
                allClear
            } else {
                List(thirsty, id: \.id) { plant in
                    HStack(spacing: 6) {
                        Text(plant.emoji)
                        Text(plant.name)
                            .font(.footnote)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "drop.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(Text("watch_plants"))
    }

    private var allClear: some View {
        VStack(spacing: 6) {
            Image(systemName: "leaf")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_all_good")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
