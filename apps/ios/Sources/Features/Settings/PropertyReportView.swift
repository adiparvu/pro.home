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

    @State private var isGenerating = false
    @State private var pdfURL: URL? = nil
    @State private var showShareSheet = false
    @State private var includesTasks = true
    @State private var includesFinances = true
    @State private var includesDocuments = true
    @State private var includesTwin = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                PageHeader(titleKey: "Raport", subtitleKey: "PROPERTY")
                heroCard
                sectionToggles
                generateButton
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.xxs)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            // Preview first, share from the preview — nobody sends a
            // document they haven't seen.
            if let url = pdfURL { ReportPreviewSheet(url: url) }
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
                        Image(systemName: "house.fill")
                            .font(AppFont.scaled(20, weight: .semibold))
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

            // Stats strip
            HStack(spacing: 0) {
                statCell(icon: "checklist",
                         value: "\(taskService.openCount)",
                         label: taskService.overdueCount > 0
                             ? "\(taskService.overdueCount) \(String(localized: "overdue"))"
                             : String(localized: "open"),
                         color: taskService.overdueCount > 0 ? .red : .blue)
                Divider().frame(height: 36).background(Color.primary.opacity(0.1))
                statCell(icon: "banknote",
                         value: financialService.moneyDisplay(financialService.currentMonthIncome),
                         label: String(localized: "this month"),
                         color: Color.brandSuccess)
                Divider().frame(height: 36).background(Color.primary.opacity(0.1))
                statCell(icon: "doc.fill",
                         value: "\(documentService.documents.count)",
                         label: documentService.expiringDocs.isEmpty
                             ? String(localized: "total")
                             : "\(documentService.expiringDocs.count) \(String(localized: "expiring"))",
                         color: documentService.expiringDocs.isEmpty ? .orange : .red)
            }
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
            Text("INCLUDE IN REPORT")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 0) {
                toggleRow("checklist", .blue, "Tasks & Maintenance", $includesTasks)
                Divider().padding(.leading, 54).background(Color.primary.opacity(AppOpacity.hairline))
                toggleRow("banknote.fill", Color.brandSuccess, "Financial summary", $includesFinances)
                Divider().padding(.leading, 54).background(Color.primary.opacity(AppOpacity.hairline))
                toggleRow("doc.text.fill", .orange, "Documents", $includesDocuments)
                Divider().padding(.leading, 54).background(Color.primary.opacity(AppOpacity.hairline))
                toggleRow("map.fill", .indigo, "Digital Twin & Zones", $includesTwin)
            }
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private func toggleRow(_ icon: String, _ color: Color, _ label: LocalizedStringKey, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        GlassWideButton(icon: "arrow.down.doc.fill", label: "Generate PDF",
                        isBusy: isGenerating) {
            Task { await generate() }
        }
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
