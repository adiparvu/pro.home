import SwiftUI
import PDFKit

struct PropertyReportView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var propertyService: PropertyService

    @State private var isGenerating = false
    @State private var pdfURL: URL? = nil
    @State private var showShareSheet = false
    @State private var includesTasks = true
    @State private var includesFinances = true
    @State private var includesDocuments = true

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Raport", subtitle: "PROPRIETATE")
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroCard
                    sectionToggles
                    generateButton
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .refreshable { }
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
                        Text("Generat · \(formattedToday)")
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
                         label: taskService.overdueCount > 0 ? "\(taskService.overdueCount) restante" : "deschise",
                         color: taskService.overdueCount > 0 ? .red : .blue)
                Divider().frame(height: 36).background(Color.primary.opacity(0.1))
                statCell(icon: "banknote",
                         value: "\(financialService.currencySymbol)\(Int(financialService.currentMonthIncome))",
                         label: "luna aceasta",
                         color: Color(red: 0.25, green: 0.82, blue: 0.5))
                Divider().frame(height: 36).background(Color.primary.opacity(0.1))
                statCell(icon: "doc.fill",
                         value: "\(documentService.documents.count)",
                         label: documentService.expiringDocs.isEmpty ? "total" : "\(documentService.expiringDocs.count) expiră",
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
                .font(.system(size: 12, weight: .semibold))
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
            Text("INCLUDE ÎN RAPORT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                toggleRow("checklist", .blue, "Sarcini & Mentenanță", $includesTasks)
                Divider().padding(.leading, 54).background(Color.primary.opacity(0.06))
                toggleRow("banknote.fill", Color(red: 0.25, green: 0.82, blue: 0.5), "Rezumat financiar", $includesFinances)
                Divider().padding(.leading, 54).background(Color.primary.opacity(0.06))
                toggleRow("doc.text.fill", .orange, "Documente", $includesDocuments)
            }
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private func toggleRow(_ icon: String, _ color: Color, _ label: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.blue)
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
                    Label("Generează PDF", systemImage: "arrow.down.doc.fill")
                        .font(.system(size: 16, weight: .semibold))
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
        f.locale = Locale(identifier: "ro_RO")
        return f.string(from: Date())
    }

    // MARK: - PDF Generation (unchanged logic)

    private func generate() async {
        isGenerating = true
        let url = await Task.detached(priority: .userInitiated) { [self] in
            return generatePDF()
        }.value
        pdfURL = url
        isGenerating = false
        HapticFeedback.success()
        showShareSheet = true
    }

    private func generatePDF() -> URL {
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
            "Generat \(now.string(from: Date()))".draw(at: CGPoint(x: 40, y: y), withAttributes: subAttr)
            y += 40

            UIColor.white.withAlphaComponent(0.1).setFill()
            g.fill(CGRect(x: 40, y: y, width: 515, height: 0.5))
            y += 20

            let bodyAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.white]
            let secondaryAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.white.withAlphaComponent(0.5)]
            let sectionAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.white.withAlphaComponent(0.4)]

            if includesTasks {
                "SARCINI & MENTENANȚĂ".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttr)
                y += 22
                "Deschise: \(taskService.openCount)   Restante: \(taskService.overdueCount)   Finalizate săptămâna aceasta: \(taskService.completedThisWeek)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 24
                for t in taskService.tasks.filter({ $0.isOverdue }).prefix(5) {
                    "  • \(t.title) — termen \(t.dueDateDisplay)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                    y += 17
                }
                y += 16
            }

            if includesFinances {
                "REZUMAT FINANCIAR".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttr)
                y += 22
                let sym = financialService.currencySymbol
                "Luna aceasta: \(sym)\(Int(financialService.currentMonthIncome)) venituri · \(sym)\(Int(financialService.currentMonthExpenses)) cheltuieli · Net: \(sym)\(Int(financialService.currentMonthNet))".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 30
            }

            if includesDocuments {
                "DOCUMENTE".draw(at: CGPoint(x: 40, y: y), withAttributes: sectionAttr)
                y += 22
                "Total: \(documentService.documents.count)   Expiră curând: \(documentService.expiringDocs.count)   Critice: \(documentService.criticalDocs.count)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 24
                for doc in documentService.expiringDocs.prefix(5) {
                    "  ⚠ \(doc.name) expiră \(doc.expiresDisplay ?? "")".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                    y += 17
                }
            }

            let footerAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.white.withAlphaComponent(0.3)]
            "Generat de PRVIO · \(now.string(from: Date()))".draw(at: CGPoint(x: 40, y: 800), withAttributes: footerAttr)
        }

        return url
    }
}
