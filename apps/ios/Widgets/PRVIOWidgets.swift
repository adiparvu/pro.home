import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct PRVIOWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PRVIOWidgetSnapshot
    let taskCatalog: [TaskCatalogEntry]
    let plantCatalog: [PlantCatalogEntry]
}

// MARK: - Shared Timeline Provider

struct PRVIOTimelineProvider: TimelineProvider {
    func makeEntry() -> PRVIOWidgetEntry {
        PRVIOWidgetEntry(
            date: Date(),
            snapshot: SharedDataStore.read() ?? PRVIOWidgetSnapshot(),
            taskCatalog: SharedDataStore.readTaskCatalog(),
            plantCatalog: SharedDataStore.readPlantCatalog()
        )
    }

    func placeholder(in context: Context) -> PRVIOWidgetEntry { makeEntry() }

    func getSnapshot(in context: Context, completion: @escaping (PRVIOWidgetEntry) -> ()) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PRVIOWidgetEntry>) -> ()) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [makeEntry()], policy: .after(next)))
    }
}

// MARK: - Widget Bundle

@main
struct PRVIOWidgetBundle: WidgetBundle {
    var body: some Widget {
        TasksWidget()
        PlantsWidget()
        DashboardWidget()
        ShoppingWidget()
        LockScreenTasksWidget()
        LockScreenPlantsWidget()
        LockScreenDashboardWidget()
        // Live Activities
        ShoppingLiveActivity()
        MaintenanceLiveActivity()
        DeliveryLiveActivity()
        PlantCareLiveActivity()
    }
}
