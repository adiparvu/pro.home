import SwiftUI

// MARK: - Export Your Data
//
// The household's data belongs to the household. One tap produces a single
// human-readable JSON file with every entity the app has loaded — tasks,
// finances, documents metadata, appliances, plants, supplies, family,
// valuations — pretty-printed and key-sorted so it diffs cleanly between
// exports. Document FILES are not embedded (they can be gigabytes); the
// screen says so instead of pretending.

struct ExportDataView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(FinancialService.self) private var financialService
    @Environment(DocumentService.self) private var documentService
    @Environment(FamilyService.self) private var familyService
    @Environment(SupplyService.self) private var supplyService
    @Environment(PlantService.self) private var plantService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PropertyValueService.self) private var propertyValueService

    @State private var exportURL: URL? = nil
    @State private var isExporting = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {

                VStack(alignment: .leading, spacing: 12) {
                    exportRow(icon: "checklist", text: "export_inc_tasks", count: taskService.tasks.count)
                    exportRow(icon: "banknote.fill", text: "export_inc_finances", count: financialService.records.count)
                    exportRow(icon: "doc.text.fill", text: "export_inc_documents", count: documentService.documents.count)
                    exportRow(icon: "washer.fill", text: "export_inc_appliances", count: applianceService.appliances.count)
                    exportRow(icon: "leaf.fill", text: "export_inc_plants", count: plantService.plants.count)
                    exportRow(icon: "cart.fill", text: "export_inc_supplies", count: supplyService.items.count)
                    exportRow(icon: "person.2.fill", text: "export_inc_family", count: familyService.members.count)
                    exportRow(icon: "camera.fill", text: "export_inc_journal", count: photoJournalService.entries.count)
                    exportRow(icon: "chart.line.uptrend.xyaxis", text: "export_inc_valuations", count: propertyValueService.entries.count)
                }
                .padding(AppSpacing.lg)
                .liquidGlass(cornerRadius: AppRadius.xl)

                Text("export_files_note")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.xxs)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        HStack(spacing: 10) {
                            Label("export_share", systemImage: "square.and.arrow.up")
                                .font(AppFont.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .glassProminent(in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    GlassWideButton(icon: "doc.badge.gearshape",
                                    label: "export_generate",
                                    isBusy: isExporting) {
                        export()
                    }
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("export_title")
        .navigationBarTitleDisplayMode(.large)
    }

    private func exportRow(icon: String, text: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(text)
                .font(AppFont.footnote)
            Spacer()
            Text(verbatim: "\(count)")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Assemble + write (encoding runs off the main actor)

    private struct ExportBundle: Encodable {
        let exportedAt: String
        let property: PropertyModel?
        let tasks: [MaintenanceTask]
        let financialRecords: [FinancialRecord]
        let documents: [DocumentModel]
        let appliances: [Appliance]
        let plants: [Plant]
        let supplyLists: [SupplyList]
        let supplyItems: [SupplyItem]
        let familyMembers: [FamilyMember]
        let photoJournal: [PhotoJournalEntry]
        let valuations: [PropertyValueEntry]
    }

    private func export() {
        isExporting = true
        let bundle = ExportBundle(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            property: propertyService.primary,
            tasks: taskService.tasks,
            financialRecords: financialService.records,
            documents: documentService.documents,
            appliances: applianceService.appliances,
            plants: plantService.plants,
            supplyLists: supplyService.lists,
            supplyItems: supplyService.items,
            familyMembers: familyService.members,
            photoJournal: photoJournalService.entries,
            valuations: propertyValueService.entries)

        Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let day = String(bundle.exportedAt.prefix(10))
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PRVIO-export-\(day).json")
            let written: URL?
            if let data = try? encoder.encode(bundle), (try? data.write(to: url)) != nil {
                written = url
            } else {
                written = nil
            }
            await MainActor.run {
                exportURL = written
                isExporting = false
            }
        }
    }
}
