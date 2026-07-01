import SwiftUI

struct IntegrationsView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @StateObject var vm = IntegrationsViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                appleEcosystemSection
                productivitySection
                localControllersSection
                smartHomeSection
                paymentsSection
                securitySection
                financeSection
                rentalsSection
                deliveriesSection
                energySection

                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
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
        .sheet(item: $vm.activeSheet) { sheet in
            switch sheet {
            case .siriShortcuts: NavigationStack { SiriShortcutsView() }
            case .nfcWallet:     NavigationStack { NFCWalletView() }
            case .iotHub:        NavigationStack { IoTHubView() }
            }
        }
    }
}
