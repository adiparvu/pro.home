import SwiftUI
import PDFKit
import MapKit

struct PropertyReportView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(FinancialService.self) private var financialService
    @Environment(DocumentService.self) private var documentService
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(PlantService.self) private var plantService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(InventoryService.self) private var inventoryService
    @Environment(FamilyService.self) private var familyService
    @Environment(PhotoJournalService.self) private var photoJournalService

    @State private var isGenerating = false
    @State private var pdfURL: URL? = nil
    @State private var showShareSheet = false

    // Section choices persist across opens — a report is configured once and
    // regenerated many times, so the selection shouldn't reset every visit.
    @AppStorage("rep_include_tasks")      private var includesTasks = true
    @AppStorage("rep_include_finances")   private var includesFinances = true
    @AppStorage("rep_include_documents")  private var includesDocuments = true
    @AppStorage("rep_include_twin")       private var includesTwin = true
    @AppStorage("rep_include_plants")     private var includesPlants = true
    @AppStorage("rep_include_appliances") private var includesAppliances = true
    @AppStorage("rep_include_inventory")  private var includesInventory = true
    @AppStorage("rep_include_tenants")    private var includesTenants = true
    @AppStorage("rep_include_journal")    private var includesJournal = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                heroCard
                sectionToggles
                generateButton
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.xxs)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Raport")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showShareSheet) {
            // Preview first, share from the preview — nobody sends a
            // document they haven't seen.
            if let url = pdfURL { ReportPreviewSheet(url: url) }
        }
        .task {
            // The report must reflect EVERYTHING, not just the pages the
            // user happened to visit this session — hydrate every empty
            // source concurrently. Cheap no-ops when already loaded.
            guard let pid = propertyService.primary?.id else { return }
            await withTaskGroup(of: Void.self) { group in
                if plantService.plants.isEmpty { group.addTask { @MainActor in await plantService.load(propertyId: pid) } }
                if applianceService.appliances.isEmpty { group.addTask { @MainActor in await applianceService.load(propertyId: pid) } }
                if inventoryService.items.isEmpty { group.addTask { @MainActor in await inventoryService.load(propertyId: pid) } }
                if photoJournalService.entries.isEmpty { group.addTask { @MainActor in await photoJournalService.load(propertyId: pid) } }
                if familyService.members.isEmpty { group.addTask { @MainActor in await familyService.load() } }
                if familyService.leases.isEmpty { group.addTask { @MainActor in await familyService.loadLeases(propertyId: pid) } }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 0) {
            // Gradient header strip
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [Color.blue, Color.indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                        // The brand monogram (P with the roof) — the same
                        // asset the FAB and QR badge stamp, not a redraw.
                        Image("BrandMark")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(propertyService.primary?.name ?? "My Home")
                            .font(AppFont.scaled(17, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Generated · \(formattedToday)")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "doc.richtext.fill")
                        .font(AppFont.scaled(18))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
            }
            .frame(height: 88)

            // Stats strip — each cell dims when its section is excluded, so
            // the card previews what the generated report will contain.
            HStack(spacing: 0) {
                statCell(icon: "checklist",
                         value: "\(taskService.openCount)",
                         label: taskService.overdueCount > 0
                             ? "\(taskService.overdueCount) \(String(localized: "overdue"))"
                             : String(localized: "open"),
                         color: taskService.overdueCount > 0 ? .red : .blue)
                    .opacity(includesTasks ? 1 : AppOpacity.disabled)
                Divider().frame(height: 36).background(Color.primary.opacity(0.1))
                statCell(icon: "banknote",
                         value: financialService.moneyDisplay(financialService.currentMonthIncome),
                         label: String(localized: "this month"),
                         color: Color.brandSuccess)
                    .opacity(includesFinances ? 1 : AppOpacity.disabled)
                Divider().frame(height: 36).background(Color.primary.opacity(0.1))
                statCell(icon: "doc.fill",
                         value: "\(documentService.documents.count)",
                         label: documentService.expiringDocs.isEmpty
                             ? String(localized: "total")
                             : "\(documentService.expiringDocs.count) \(String(localized: "expiring"))",
                         color: documentService.expiringDocs.isEmpty ? .orange : .red)
                    .opacity(includesDocuments ? 1 : AppOpacity.disabled)
            }
            .animation(AppMotion.state, value: includesTasks)
            .animation(AppMotion.state, value: includesFinances)
            .animation(AppMotion.state, value: includesDocuments)
            .padding(.vertical, AppSpacing.base)
            .background(Color.primary.opacity(0.04))
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func statCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(AppFont.captionStrong)
                .foregroundStyle(color)
            Text(value)
                .font(AppFont.scaled(15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(AppFont.scaled(10))
                .foregroundStyle(Color.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Toggles

    private var sectionToggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Include in Report")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 0) {
                toggleRow("checklist", .blue, "Tasks & Maintenance", $includesTasks)
                rowDivider
                toggleRow("banknote.fill", Color.brandSuccess, "Financial summary", $includesFinances)
                rowDivider
                toggleRow("doc.text.fill", .orange, "Documents", $includesDocuments)
                rowDivider
                toggleRow("leaf.fill", .green, "rep_sec_plants", $includesPlants,
                          count: plantService.plants.count)
                rowDivider
                toggleRow("washer.fill", .teal, "rep_sec_appliances", $includesAppliances,
                          count: applianceService.appliances.count)
                rowDivider
                toggleRow("shippingbox.fill", .brown, "rep_sec_inventory", $includesInventory,
                          count: inventoryService.items.count)
                rowDivider
                toggleRow("person.2.fill", .purple, "rep_sec_tenants", $includesTenants,
                          count: tenants.count)
                rowDivider
                toggleRow("photo.on.rectangle.angled", .pink, "rep_sec_journal", $includesJournal,
                          count: photoJournalService.entries.count)
                rowDivider
                toggleRow("map.fill", .indigo, "Digital Twin & Zones", $includesTwin)
            }
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 54).background(Color.primary.opacity(AppOpacity.hairline))
    }

    /// A section toggle. Rows with a live `count` show it as a pill; when
    /// the count is zero the row is disabled and dimmed — an empty section
    /// can't be included, so the PDF never renders a header with nothing
    /// under it.
    private func toggleRow(_ icon: String, _ color: Color, _ label: LocalizedStringKey,
                           _ binding: Binding<Bool>, count: Int? = nil) -> some View {
        let isEmpty = count == 0
        return HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(AppFont.scaled(12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondaryTextColor)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.subtleFill, in: Capsule())
                    .monospacedDigit()
            }
            Toggle("", isOn: isEmpty ? .constant(false) : binding)
                .labelsHidden()
                .tint(.accentColor)
                .disabled(isEmpty)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .opacity(isEmpty ? AppOpacity.secondaryText : 1)
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        GlassWideButton(icon: "arrow.down.doc.fill", label: "Generate PDF",
                        isBusy: isGenerating) {
            Task { await generate() }
        }
    }

    // MARK: - Section data

    /// Tenants on the current roster (`family_members` rows with role
    /// "tenant") — the same filter TenantManagementView uses.
    private var tenants: [FamilyMember] {
        familyService.members.filter { $0.role == "tenant" }
    }

    /// Expected monthly rent, summed per currency so mixed-currency leases
    /// are never added together ("1.200 EUR + 500 USD"), or "—" when no
    /// lease captures a rent.
    private var expectedRentDisplay: String {
        let rents = tenants
            .compactMap { familyService.leases[$0.id] }
            .compactMap { lease in lease.monthlyRent.map { (lease.currency, $0) } }
        guard !rents.isEmpty else { return "—" }
        return Dictionary(grouping: rents, by: \.0)
            .map { "\(CurrencyService.amount($0.value.reduce(0) { $0 + $1.1 })) \($0.key)" }
            .sorted()
            .joined(separator: " + ")
    }

    /// The five most recent journal captures — count + captions only; the
    /// report stays lightweight by never embedding the photos themselves.
    private var recentJournalEntries: [PhotoJournalEntry] {
        Array(photoJournalService.entries
            .sorted { ($0.takenDate ?? .distantPast) > ($1.takenDate ?? .distantPast) }
            .prefix(5))
    }

    private var latestJournalDisplay: String {
        photoJournalService.entries.compactMap(\.takenDate).max()
            .map { AppDate.medium.string(from: $0) } ?? "—"
    }

    /// A day-string ("2026-08-01" or ISO timestamp) formatted for print —
    /// same parsing chain `Appliance` uses internally.
    private func dayDisplay(_ raw: String?) -> String {
        guard let raw else { return "—" }
        guard let d = ISODate.date(from: raw) ?? AppDate.day(from: raw) else { return raw }
        return AppDate.medium.string(from: d)
    }

    // MARK: - Helpers

    private var formattedToday: String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        f.locale = .current
        return f.string(from: Date())
    }

    // MARK: - PDF Generation (unchanged logic)

    private func generate() async {
        isGenerating = true
        let twinImage = includesTwin ? await twinSnapshot() : nil
        // generatePDF reads main-actor service/view state (properties, zones,
        // elements, toggles), so it must run on the main actor — detaching it
        // was a latent data race. The render is fast and the spinner is
        // already visible from the awaited snapshot above.
        let url = generatePDF(twinImage: twinImage)
        pdfURL = url
        isGenerating = false
        HapticFeedback.success()
        showShareSheet = true
    }

    // MARK: - Twin map snapshot

    private func twinRegion() -> MKCoordinateRegion {
        let pts = zoneService.zones.flatMap { $0.polygon }
        if pts.isEmpty {
            let center = CLLocationCoordinate2D(
                latitude: propertyService.primary?.latitude ?? 44.4268,
                longitude: propertyService.primary?.longitude ?? 26.1025)
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002))
        }
        let lats = pts.map(\.lat), lons = pts.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            let fallbackCenter = CLLocationCoordinate2D(
                latitude: propertyService.primary?.latitude ?? 44.4268,
                longitude: propertyService.primary?.longitude ?? 26.1025)
            return MKCoordinateRegion(center: fallbackCenter, span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002))
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.001),
                                    longitudeDelta: max((maxLon - minLon) * 1.5, 0.001))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func twinSnapshot() async -> UIImage? {
        let opts = MKMapSnapshotter.Options()
        opts.region = twinRegion()
        opts.size = CGSize(width: 515, height: 280)
        opts.mapType = .hybrid
        let snapshotter = MKMapSnapshotter(options: opts)
        guard let snapshot = try? await snapshotter.start() else { return nil }
        let zones = zoneService.zones
        let renderer = UIGraphicsImageRenderer(size: opts.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            for zone in zones where zone.isDrawable {
                let pts = zone.coordinates.map { snapshot.point(for: $0) }
                guard let first = pts.first else { continue }
                let path = UIBezierPath()
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
                path.close()
                let color = UIColor(zone.tint)
                color.withAlphaComponent(0.3).setFill(); path.fill()
                color.setStroke(); path.lineWidth = 2; path.stroke()
            }
        }
    }

    private func generatePDF(twinImage: UIImage? = nil) -> URL {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let now = DateFormatter()
        now.dateStyle = .long
        let dateLine = now.string(from: Date())

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRVIO_Report_\(Date().timeIntervalSince1970).pdf")

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13),
            .foregroundColor: UIColor.white.withAlphaComponent(0.5)
        ]
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.white
        ]
        let sectionAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.4)
        ]
        let footerAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.white.withAlphaComponent(0.3)
        ]

        try? renderer.writePDF(to: url) { ctx in
            var page = PDFCursor(
                ctx: ctx, pageRect: pageRect,
                footer: String(format: String(localized: "report_pdf_footer %@"), dateLine),
                footerAttr: footerAttr)
            page.newPage()

            let title = propertyService.primary?.name ?? String(localized: "report_pdf_title_fallback")
            page.draw(title, titleAttr, advance: 40)
            page.draw(String(format: String(localized: "report_pdf_generated %@"), dateLine),
                      subAttr, advance: 40)
            page.rule()

            if includesTasks {
                page.draw(String(localized: "report_pdf_tasks"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "report_pdf_tasks_line %lld %lld %lld"),
                                 taskService.openCount, taskService.overdueCount,
                                 taskService.completedThisWeek),
                          bodyAttr, advance: 24)
                // The full overdue list — the cursor breaks pages, so the
                // report no longer silently stops at five items.
                for t in taskService.tasks.filter({ $0.isOverdue }) {
                    page.draw("  " + String(format: String(localized: "report_pdf_task_due %@ %@"),
                                            t.title, t.dueDateDisplay),
                              bodyAttr, advance: 17)
                }
                page.space(16)
            }

            if includesFinances {
                page.draw(String(localized: "report_pdf_finances"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "report_pdf_fin_line %@ %@ %@"),
                                 financialService.moneyDisplay(financialService.currentMonthIncome),
                                 financialService.moneyDisplay(financialService.currentMonthExpenses),
                                 financialService.moneyDisplay(financialService.currentMonthNet)),
                          bodyAttr, advance: 30)
            }

            if includesDocuments {
                page.draw(String(localized: "report_pdf_documents"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "report_pdf_docs_line %lld %lld %lld"),
                                 documentService.documents.count,
                                 documentService.expiringDocs.count,
                                 documentService.criticalDocs.count),
                          bodyAttr, advance: 24)
                for doc in documentService.expiringDocs {
                    page.draw("  " + String(format: String(localized: "report_pdf_doc_expires %@ %@"),
                                            doc.name, doc.expiresDisplay ?? ""),
                              bodyAttr, advance: 17)
                }
                page.space(16)
            }

            // The living-and-assets sections render only when they have real
            // rows behind them — a header over nothing is a lie, so empty
            // sections are skipped even if their toggle survived in storage.

            if includesPlants && !plantService.plants.isEmpty {
                page.draw(String(localized: "rep_pdf_plants"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "rep_pdf_plants_line %lld %lld %lld"),
                                 plantService.plants.count,
                                 plantService.plantsNeedingWater.count,
                                 plantService.criticalPlants.count),
                          bodyAttr, advance: 24)
                for plant in plantService.plantsNeedingWater {
                    page.draw("  " + String(format: String(localized: "rep_pdf_plant_water %@"), plant.name),
                              bodyAttr, advance: 17)
                }
                page.space(16)
            }

            if includesAppliances && !applianceService.appliances.isEmpty {
                page.draw(String(localized: "rep_pdf_appliances"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "rep_pdf_appliances_line %lld %lld"),
                                 applianceService.appliances.count,
                                 applianceService.appliancesExpiringWarranty.count),
                          bodyAttr, advance: 24)
                for appliance in applianceService.appliancesExpiringWarranty {
                    page.draw("  " + String(format: String(localized: "rep_pdf_appliance_warranty %@ %@"),
                                            appliance.name, dayDisplay(appliance.warrantyUntil)),
                              bodyAttr, advance: 17)
                }
                page.space(16)
            }

            if includesInventory && !inventoryService.items.isEmpty {
                page.draw(String(localized: "rep_pdf_inventory"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "rep_pdf_inventory_line %lld %@ %lld"),
                                 inventoryService.items.count,
                                 CurrencyService.money(inventoryService.totalValue, code: "EUR", whole: true),
                                 inventoryService.loanedCount),
                          bodyAttr, advance: 24)
                for item in inventoryService.items.filter(\.isLoaned) {
                    page.draw("  " + String(format: String(localized: "rep_pdf_inv_loan %@ %@"),
                                            item.name, item.currentLoan?.borrowerName ?? "—"),
                              bodyAttr, advance: 17)
                }
                page.space(16)
            }

            if includesTenants && !tenants.isEmpty {
                page.draw(String(localized: "rep_pdf_tenants"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "rep_pdf_tenants_line %lld %@"),
                                 tenants.count, expectedRentDisplay),
                          bodyAttr, advance: 24)
                for tenant in tenants {
                    let lease = familyService.leases[tenant.id]
                    let details = [
                        lease?.rentDisplay,
                        lease?.endDisplay.map {
                            String(format: String(localized: "rep_pdf_until %@"), $0)
                        }
                    ].compactMap { $0 }.joined(separator: " · ")
                    page.draw("  \(tenant.name) — \(details.isEmpty ? "—" : details)",
                              bodyAttr, advance: 17)
                }
                page.space(16)
            }

            if includesJournal && !photoJournalService.entries.isEmpty {
                page.draw(String(localized: "rep_pdf_journal"), sectionAttr, advance: 22)
                page.draw(String(format: String(localized: "rep_pdf_journal_line %lld %@"),
                                 photoJournalService.entries.count, latestJournalDisplay),
                          bodyAttr, advance: 24)
                for entry in recentJournalEntries {
                    let date = entry.takenDate.map { AppDate.medium.string(from: $0) } ?? "—"
                    page.draw("  \(date) — \(entry.title)", bodyAttr, advance: 17)
                }
            }

            if includesTwin {
                page.newPage()
                page.draw(String(localized: "report_pdf_twin"), titleAttr, advance: 44)
                if let twinImage {
                    page.image(twinImage, height: 280)
                }
                page.draw(String(format: String(localized: "report_pdf_twin_line %lld %lld %lld"),
                                 zoneService.zones.count, elementService.elements.count,
                                 elementService.overallHealthScore),
                          bodyAttr, advance: 28)
                page.draw(String(localized: "report_pdf_zones"), sectionAttr, advance: 20)
                for zone in zoneService.zones {
                    let count = elementService.elements(inZone: zone.id).count
                    page.draw("  " + String(format: String(localized: "report_pdf_zone_line %@ %lld %lld"),
                                            zone.name, zone.healthScore, count),
                              bodyAttr, advance: 17)
                }
            }
        }

        return url
    }
}

// MARK: - PDF layout cursor
//
// A vertical cursor with automatic page breaks: every page it opens gets
// the dark background and the footer, and any draw that would collide with
// the footer flows onto a fresh page — so long lists paginate instead of
// being truncated or drawn off-canvas.

private struct PDFCursor {
    let ctx: UIGraphicsPDFRendererContext
    let pageRect: CGRect
    let footer: String
    let footerAttr: [NSAttributedString.Key: Any]
    var y: CGFloat = 40

    private var margin: CGFloat { 40 }
    private var bottomLimit: CGFloat { pageRect.height - 60 }

    mutating func newPage() {
        ctx.beginPage()
        UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1).setFill()
        ctx.cgContext.fill(pageRect)
        footer.draw(at: CGPoint(x: margin, y: pageRect.height - 42), withAttributes: footerAttr)
        y = 40
    }

    mutating func ensure(_ height: CGFloat) {
        if y + height > bottomLimit { newPage() }
    }

    mutating func draw(_ text: String, _ attr: [NSAttributedString.Key: Any], advance: CGFloat) {
        ensure(advance)
        text.draw(at: CGPoint(x: margin, y: y), withAttributes: attr)
        y += advance
    }

    mutating func space(_ height: CGFloat) {
        y += height
    }

    mutating func rule() {
        ensure(21)
        UIColor.white.withAlphaComponent(0.1).setFill()
        ctx.cgContext.fill(CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: 0.5))
        y += 20
    }

    mutating func image(_ image: UIImage, height: CGFloat) {
        ensure(height + 20)
        let rect = CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: height)
        image.draw(in: rect)
        UIColor.white.withAlphaComponent(0.12).setStroke()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        border.lineWidth = 1
        border.stroke()
        y += height + 20
    }
}

// MARK: - Report preview

private struct ReportPreviewSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReportPDFView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("report_preview_title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(AppFont.footnoteEmphasis)
                        }
                        .accessibilityLabel(Text("Close"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url)
                    }
                }
        }
    }
}

private struct ReportPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
