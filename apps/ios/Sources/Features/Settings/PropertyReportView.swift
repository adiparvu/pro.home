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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                previewCard
                contentToggles
                generateButton
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Property Report")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL { ShareSheet(url: url) }
        }
    }

    private var previewCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "doc.richtext.fill", color: .blue, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(propertyService.primary?.name ?? "Property Report")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                        Text("Generated \(formattedToday)")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                    Spacer()
                }
                Divider().background(Color.primary.opacity(0.07))
                VStack(spacing: 8) {
                    reportInfoRow("Tasks", "\(taskService.openCount) open, \(taskService.overdueCount) overdue")
                    reportInfoRow("Finances", "\(financialService.currencySymbol)\(Int(financialService.currentMonthIncome)) income this month")
                    reportInfoRow("Documents", "\(documentService.documents.count) total, \(documentService.expiringDocs.count) expiring")
                }
            }
        }
    }

    @State private var includesTasks = true
    @State private var includesFinances = true
    @State private var includesDocuments = true

    private var contentToggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INCLUDE IN REPORT")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.35)).padding(.leading, 4)

            VStack(spacing: 0) {
                toggleRow("checklist", .blue, "Tasks & Maintenance", $includesTasks)
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                toggleRow("banknote.fill", Color(red: 0.3, green: 0.85, blue: 0.5), "Financial Summary", $includesFinances)
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                toggleRow("doc.text.fill", .orange, "Documents", $includesDocuments)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private var generateButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                    Text("Generate PDF")
                }
            }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).disabled(isGenerating)
    }

    private var formattedToday: String {
        let f = DateFormatter(); f.dateStyle = .long; return f.string(from: Date())
    }

    private func reportInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
        }
    }

    private func toggleRow(_ icon: String, _ color: Color, _ label: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label).font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().tint(.blue)
        }.padding(.horizontal, 14).padding(.vertical, 12)
    }

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
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let now = DateFormatter()
        now.dateStyle = .long

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PRVIO_Report_\(Date().timeIntervalSince1970).pdf")

        try? renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            let g = ctx.cgContext

            // Background
            UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1).setFill()
            g.fill(pageRect)

            var y: CGFloat = 40

            // Title
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

            // Divider
            UIColor.white.withAlphaComponent(0.1).setFill()
            g.fill(CGRect(x: 40, y: y, width: 515, height: 0.5))
            y += 20

            let bodyAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.white]
            let boldAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor.white]
            let secondaryAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.white.withAlphaComponent(0.5)]

            // Tasks section
            if includesTasks {
                "TASKS & MAINTENANCE".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.white.withAlphaComponent(0.4)])
                y += 22
                "Open Tasks: \(taskService.openCount)   Overdue: \(taskService.overdueCount)   Completed this week: \(taskService.completedThisWeek)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 24
                let overdueList = taskService.tasks.filter { $0.isOverdue }.prefix(5)
                if !overdueList.isEmpty {
                    "Overdue:".draw(at: CGPoint(x: 40, y: y), withAttributes: secondaryAttr); y += 18
                    for t in overdueList {
                        "  • \(t.title) — due \(t.dueDateDisplay)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr); y += 17
                    }
                }
                y += 16
            }

            // Finances section
            if includesFinances {
                "FINANCIAL SUMMARY".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.white.withAlphaComponent(0.4)])
                y += 22
                let sym = financialService.currencySymbol
                "This month: \(sym)\(Int(financialService.currentMonthIncome)) income · \(sym)\(Int(financialService.currentMonthExpenses)) expenses · Net: \(sym)\(Int(financialService.currentMonthNet))".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 30
            }

            // Documents section
            if includesDocuments {
                "DOCUMENTS".draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.white.withAlphaComponent(0.4)])
                y += 22
                "Total: \(documentService.documents.count)   Expiring soon: \(documentService.expiringDocs.count)   Critical: \(documentService.criticalDocs.count)".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr)
                y += 24
                for doc in documentService.expiringDocs.prefix(5) {
                    "  ⚠ \(doc.name) expires \(doc.expiresDisplay ?? "")".draw(at: CGPoint(x: 40, y: y), withAttributes: bodyAttr); y += 17
                }
            }

            // Footer
            let footerAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.white.withAlphaComponent(0.3)]
            "Generated by PRVIO · \(now.string(from: Date()))".draw(at: CGPoint(x: 40, y: 800), withAttributes: footerAttr)
        }

        return url
    }
}

