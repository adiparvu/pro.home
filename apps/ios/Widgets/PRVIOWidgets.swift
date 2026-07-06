import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline Entry

struct PRVIOWidgetEntry: TimelineEntry {
    let date: Date
    var relevance: TimelineEntryRelevance?
    let snapshot: PRVIOWidgetSnapshot
    let taskCatalog: [TaskCatalogEntry]
    let plantCatalog: [PlantCatalogEntry]
    var supplyCatalog: [SupplyCatalogEntry] = []
}

// MARK: - Shared Timeline Provider

struct PRVIOTimelineProvider: TimelineProvider {
    func makeEntry() -> PRVIOWidgetEntry {
        let snap = SharedDataStore.read() ?? PRVIOWidgetSnapshot()
        let urgency = snap.overdueTaskCount + snap.plantsNeedingWater
        let relevance = urgency > 0
            ? TimelineEntryRelevance(score: min(Float(urgency) * 2.5, 10.0), duration: 3600)
            : TimelineEntryRelevance(score: 0.5, duration: 900)
        return PRVIOWidgetEntry(
            date: Date(),
            relevance: relevance,
            snapshot: snap,
            taskCatalog: SharedDataStore.readTaskCatalog(),
            plantCatalog: SharedDataStore.readPlantCatalog(),
            supplyCatalog: SharedDataStore.readSupplyCatalog()
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
        BrandWidget()
        TasksWidget()
        PlantsWidget()
        DashboardWidget()
        ShoppingWidget()
        LockScreenTasksWidget()
        LockScreenPlantsWidget()
        LockScreenDashboardWidget()
        LockScreenHealthWidget()
        LockScreenDeliveriesWidget()
        LockScreenMessagesWidget()
        LockScreenNextTaskWidget()
        // Live Activities
        ShoppingLiveActivity()
        MaintenanceLiveActivity()
        DeliveryLiveActivity()
        PlantCareLiveActivity()
        // Notification Center + Smart Stack
        NotificationCenterWidget()
        // Control Center (iOS 18+)
        if #available(iOS 18.0, *) {
            AddTaskControl()
            OpenChatControl()
            ShoppingControl()
            ScanControl()
            PlantsControl()
            DeliveriesControl()
            FinancesControl()
            DocumentsControl()
            DigitalTwinControl()
            AssistantControl()
        }
    }
}
