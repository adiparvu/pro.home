import SwiftUI

struct IntegrationsView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
    @StateObject var vm = IntegrationsViewModel()

    var body: some View {
        List {
            Section("iOS & Apple Ecosystem") {
                Label("Siri & Shortcuts", systemImage: "mic.fill")
                Label("Apple Calendar", systemImage: "calendar")
                Label("Apple Reminders", systemImage: "checklist")
                Label("Apple Contacts", systemImage: "person.2.fill")
            }
            Section("Smart Home") {
                Label("Apple HomeKit", systemImage: "homekit")
            }
            Section("Payments") {
                Label("Apple Pay", systemImage: "creditcard.fill")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.large)
        // NO .task modifiers — no service access at all
        .alert("Access Denied", isPresented: $vm.showPermissionDenied) {
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow access in Settings.")
        }
    }
}
