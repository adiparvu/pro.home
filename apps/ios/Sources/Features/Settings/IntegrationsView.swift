import SwiftUI

struct IntegrationsView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
    @StateObject var vm = IntegrationsViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                appleEcosystemSection
                productivitySection
                smartHomeSection
                securitySection
                financeSection
                rentalsSection
                energySection

                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .trackTabScroll()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.large)
        .task { await vm.checkStatuses() }
        .task { vm.tasks = taskService.tasks }
        .task { vm.property = propertyService.primary }
        .task { vm.familyMembers = familyService.members }
        .alert("Calendar Sync Enabled", isPresented: $vm.showCalendarSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your upcoming tasks will appear in your Apple Calendar under the \"PRVIO\" calendar.")
        }
        .alert("Contacts Synced", isPresented: $vm.showContactsSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Family members have been added to your Contacts under the \"PRVIO Family\" group.")
        }
        .alert("Access Denied", isPresented: $vm.showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow access in Settings to enable this integration.")
        }
    }
}
