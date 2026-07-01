import SwiftUI
import PDFKit
import MapKit

struct PropertyReportView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var zoneService: PropertyZoneService
    @EnvironmentObject private var elementService: PropertyElementService

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
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL { ShareSheet(url: url) }
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
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(propertyService.primary?.name ?? "My Home")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Generated · \(formattedToday)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
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
                         value: "\(financialService.currencySymbol)\(Int(financialService.currentMonthIncome))",
                         label: String(localized: "this month"),
                         color: Color(red: 0.25, green: 0.82, blue: 0.5))
                Divider().frame(height: 36).background(Color.primary.opacity(0.1))
                statCell(icon: "doc.fill",
                         value: "\(documentService.documents.count)",
                         label: documentService.expiringDocs.isEmpty
                             ? String(localized: "total")
                             : "\(documentService.expiringDocs.count) \(String(localized: "expiring"))",
                         color: documentService.expiringDocs.isEmpty ? .orange : .red)
            }
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.04))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func statCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(AppFont.captionStrong)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Toggles

    private var sectionToggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INCLUDE IN REPORT")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                toggleRow("checklist", .blue, "Tasks & Maintenance", $includesTasks)
                Divider().padding(.leading, 54).background(Color.primary.opacity(0.06))
                toggleRow("banknote.fill", Color(red: 0.25, green: 0.82, blue: 0.5), "Financial summary", $includesFinances)
                Divider().padding(.leading, 54).background(Color.primary.opacity(0.06))
                toggleRow("doc.text.fill", .orange, "Documents", $includesDocuments)
                Divider().padding(.leading, 54).background(Color.primary.opacity(0.06))
                toggleRow("map.fill", .indigo, "Digital Twin & Zones", $includesTwin)
            }
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private func toggleRow(_ icon: String, _ color: Color, _ label: LocalizedStringKey, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            Task { await generate() }
        } label: {
            ZStack {
                LinearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Label("Generate PDF", systemImage: "arrow.down.doc.fill")
                        .font(AppFont.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .shadow(color: .blue.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
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
        let url = await Task.detached(priority: .userInitiated) { [self] in
            return generatePDF(twinImage: twinImage)
        }.value
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

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRVIO_Report_\(Date().timeIntervalSince1970).pdf")

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            let g = ctx.cgContext

            UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1).setFill()
            g.fill(pageRect)

            var y: CGFloat = 40

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let title = propertyService.primary?.name ?? "Property Report"
            title.draw(at: CGPoint(x: 40, y: y), withAttributes: titleAttr)
            y += 40

            let subAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
            "Generated \(now.string(from: Date()))".draw(at: CGPoint(x: 40, y: y), withAttributes: subAttr)
            y += 40

            UIColor.white.withAlphaComponent(0.1).setFill()
            g.fill(CGRect(x: 40, y: y, width: 515, height: 0.5))
            y += 20

            let bodyAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.white]
            let secondaryAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.white.withAlphaComponent(0.5)]
            let sectionAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.white.withAlphaComponent(0.4)]

            if includesTasks {
                "TASKS & MAINTENANCE".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttr)
                y += 22
                "Open: \(taskService.openCount)   Overdue: \(taskService.overdueCount)   Completed this week: \(taskService.completedThisWeek)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 24
                for t in taskService.tasks.filter({ $0.isOverdue }).prefix(5) {
                    "  • \(t.title) — due \(t.dueDateDisplay)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                    y += 17
                }
                y += 16
            }

            if includesFinances {
                "FINANCIAL SUMMARY".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttr)
                y += 22
                let sym = financialService.currencySymbol
                "This month: \(sym)\(Int(financialService.currentMonthIncome)) income · \(sym)\(Int(financialService.currentMonthExpenses)) expenses · Net: \(sym)\(Int(financialService.currentMonthNet))".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 30
            }

            if includesDocuments {
                "DOCUMENTS".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttr)
                y += 22
                "Total: \(documentService.documents.count)   Expiring soon: \(documentService.expiringDocs.count)   Critical: \(documentService.criticalDocs.count)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 24
                for doc in documentService.expiringDocs.prefix(5) {
                    "  ⚠ \(doc.name) expires \(doc.expiresDisplay ?? "")".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                    y += 17
                }
            }

            let footerAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.white.withAlphaComponent(0.3)]
            "Generated by PRVIO · \(now.string(from: Date()))".draw(at: CGPoint(x: 40, y: 800), withAttributes: footerAttr)

            // Digital Twin page
            if includesTwin {
                ctx.beginPage()
                UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1).setFill()
                g.fill(pageRect)
                var ty: CGFloat = 40
                "DIGITAL TWIN".draw(at: CGPoint(x: 40, y: ty), withAttributes: titleAttr)
                ty += 44

                if let twinImage {
                    let rect = CGRect(x: 40, y: ty, width: 515, height: 280)
                    twinImage.draw(in: rect)
                    UIColor.white.withAlphaComponent(0.12).setStroke()
                    let border = UIBezierPath(roundedRect: rect, cornerRadius: 10)
                    border.lineWidth = 1; border.stroke()
                    ty += 300
                }

                "Zones: \(zoneService.zones.count)   Objects: \(elementService.elements.count)   Average health: \(elementService.overallHealthScore)%"
                    .draw(at: CGPoint(x: 40, y: ty), withAttributes: bodyAttr)
                ty += 28
                "ZONES".draw(at: CGPoint(x: 40, y: ty), withAttributes: sectionAttr)
                ty += 20
                for zone in zoneService.zones.prefix(12) {
                    let count = elementService.elements(inZone: zone.id).count
                    "  • \(zone.name) — \(zone.healthScore)%  ·  \(count) objects"
                        .draw(at: CGPoint(x: 40, y: ty), withAttributes: bodyAttr)
                    ty += 17
                }
                "Generated by PRVIO · \(now.string(from: Date()))".draw(at: CGPoint(x: 40, y: 800), withAttributes: footerAttr)
            }
        }

        return url
    }
}
