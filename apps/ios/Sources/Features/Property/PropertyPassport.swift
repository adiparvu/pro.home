import SwiftUI
import UIKit

// MARK: - Property Passport
//
// The dossier that turns years of PRVIO use into value at the table: one
// shareable PDF with the property's facts, valid documents, maintenance
// history, twelve-month finances, appliances with warranties and the value
// timeline. Built entirely from data that already lives in the services —
// generated on-device, shared through the system sheet, nothing uploaded.

enum PropertyPassport {

    struct Input {
        let property: PropertyModel
        let tasks: [MaintenanceTask]
        let documents: [DocumentModel]
        let records: [FinancialRecord]
        let appliances: [Appliance]
        let valuations: [PropertyValueEntry]
        let preferredCurrency: String
    }

    /// A4 in points.
    private static let pageSize = CGSize(width: 595, height: 842)

    /// Renders the passport and returns the PDF's temporary file URL.
    @MainActor
    static func generate(_ input: Input) -> URL? {
        let pages: [AnyView] = [
            AnyView(CoverPage(input: input)),
            AnyView(DocumentsPage(input: input)),
            AnyView(MaintenancePage(input: input)),
            AnyView(FinancePage(input: input)),
            AnyView(AppliancesPage(input: input)),
        ]

        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                let imageRenderer = ImageRenderer(
                    content: page
                        .frame(width: pageSize.width, height: pageSize.height)
                        .background(Color.white)
                        .environment(\.colorScheme, .light)
                )
                imageRenderer.scale = 2
                guard let image = imageRenderer.uiImage else { continue }
                context.beginPage()
                image.draw(in: bounds)
                drawFooter(in: context.cgContext, page: index + 1, of: pages.count)
            }
        }
        guard !data.isEmpty else { return nil }

        let safeName = input.property.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRVIO-Passport-\(safeName).pdf")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private static func drawFooter(in context: CGContext, page: Int, of total: Int) {
        let text = "PRVIO · \(AppDate.dayString(from: Date())) · \(page)/\(total)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.gray,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: pageSize.width - size.width - 24, y: pageSize.height - 20),
            withAttributes: attributes)
    }

    // MARK: - Shared page chrome

    private struct PageChrome<Content: View>: View {
        let title: LocalizedStringKey
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                    Text(verbatim: "PRVIO")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color(red: 0.15, green: 0.3, blue: 0.6))
                }
                Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
                content
                Spacer(minLength: 0)
            }
            .padding(36)
            .foregroundStyle(.black)
        }
    }

    private static func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 11)).foregroundStyle(.gray)
                .frame(width: 170, alignment: .leading)
            Text(value).font(AppFont.caption2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Pages

    private struct CoverPage: View {
        let input: Input

        var body: some View {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "house.fill")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color(red: 0.15, green: 0.3, blue: 0.6))
                Text("passport_title")
                    .font(.system(size: 26, weight: .bold))
                Text(input.property.name)
                    .font(AppFont.title3)
                Text(verbatim: "\(input.property.addressLine1), \(input.property.city)")
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
                if let score = input.property.healthScore {
                    Text(verbatim: String(format: String(localized: "passport_health"), score))
                        .font(AppFont.captionEmphasis)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color(red: 0.15, green: 0.3, blue: 0.6).opacity(0.1),
                                    in: Capsule())
                }
                Spacer()
                Text(verbatim: String(format: String(localized: "passport_generated"),
                                      AppDate.dayString(from: Date())))
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                Spacer().frame(height: 30)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.black)
        }
    }

    private struct DocumentsPage: View {
        let input: Input

        private var valid: [DocumentModel] { Array(input.documents.prefix(22)) }

        var body: some View {
            PageChrome(title: "passport_sec_documents") {
                if valid.isEmpty {
                    Text("passport_none").font(.system(size: 11)).foregroundStyle(.gray)
                }
                ForEach(valid) { doc in
                    PropertyPassport.row(
                        doc.name,
                        [String(localized: String.LocalizationValue(doc.category.capitalized)),
                         doc.expiresDisplay.map {
                             String(format: String(localized: "passport_expires"), $0)
                         }].compactMap { $0 }.joined(separator: " · "))
                }
            }
        }
    }

    private struct MaintenancePage: View {
        let input: Input

        private var completed: [MaintenanceTask] {
            Array(input.tasks.filter(\.isCompleted)
                .sorted { ($0.dueDate ?? "") > ($1.dueDate ?? "") }
                .prefix(22))
        }

        var body: some View {
            PageChrome(title: "passport_sec_maintenance") {
                PropertyPassport.row(String(localized: "passport_tasks_done"),
                                     "\(input.tasks.filter(\.isCompleted).count)")
                PropertyPassport.row(String(localized: "passport_tasks_open"),
                                     "\(input.tasks.filter { !$0.isCompleted }.count)")
                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.7)
                if completed.isEmpty {
                    Text("passport_none").font(.system(size: 11)).foregroundStyle(.gray)
                }
                ForEach(completed) { task in
                    PropertyPassport.row(task.dueDateDisplay, task.title)
                }
            }
        }
    }

    private struct FinancePage: View {
        let input: Input

        /// Expenses in the last 12 months, in the record's own currency sums
        /// per category — mixed currencies are listed per currency, honestly,
        /// instead of being silently added together.
        private var byCategory: [(String, [(String, Double)])] {
            let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date()
            let recent = input.records.filter {
                $0.type == "expense" && (AppDate.day(from: $0.date) ?? .distantPast) >= cutoff
            }
            let groups = Dictionary(grouping: recent, by: \.category)
            return groups.map { category, records in
                let perCurrency = Dictionary(grouping: records, by: \.currency)
                    .map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
                    .sorted { $0.1 > $1.1 }
                return (category, perCurrency)
            }
            .sorted { ($0.1.first?.1 ?? 0) > ($1.1.first?.1 ?? 0) }
        }

        var body: some View {
            PageChrome(title: "passport_sec_finances") {
                Text("passport_finances_note")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                ForEach(byCategory, id: \.0) { category, sums in
                    PropertyPassport.row(
                        String(localized: String.LocalizationValue(category.capitalized)),
                        sums.map { CurrencyService.money($1, code: $0, whole: true) }
                            .joined(separator: " + "))
                }
                if byCategory.isEmpty {
                    Text("passport_none").font(.system(size: 11)).foregroundStyle(.gray)
                }
                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 0.7)
                Text("passport_sec_valuations")
                    .font(.system(size: 13, weight: .bold))
                ForEach(Array(input.valuations.prefix(8))) { entry in
                    PropertyPassport.row(
                        entry.enteredDate.map { AppDate.dayString(from: $0) } ?? entry.enteredAt,
                        CurrencyService.money(entry.valueAmount, code: entry.currency, whole: true))
                }
                if input.valuations.isEmpty {
                    Text("passport_none").font(.system(size: 11)).foregroundStyle(.gray)
                }
            }
        }
    }

    private struct AppliancesPage: View {
        let input: Input

        var body: some View {
            PageChrome(title: "passport_sec_appliances") {
                if input.appliances.isEmpty {
                    Text("passport_none").font(.system(size: 11)).foregroundStyle(.gray)
                }
                ForEach(Array(input.appliances.prefix(22))) { appliance in
                    PropertyPassport.row(
                        [appliance.brand, appliance.name].compactMap { $0 }.joined(separator: " "),
                        appliance.warrantyUntil.flatMap { AppDate.day(from: $0) }.map {
                            String(format: String(localized: "passport_warranty"),
                                   AppDate.dayString(from: $0))
                        } ?? String(localized: "passport_no_warranty"))
                }
            }
        }
    }
}

// MARK: - Sheet (generate + share)

struct PropertyPassportSheet: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(FinancialService.self) private var financialService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PropertyValueService.self) private var propertyValueService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    @State private var pdfURL: URL?
    @State private var isGenerating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 84, height: 84)
                    .glassCircle()
                VStack(spacing: 6) {
                    Text("passport_title")
                        .font(AppFont.headline)
                    Text("passport_sheet_note")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }
                Spacer()

                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("passport_share", systemImage: "square.and.arrow.up")
                            .font(AppFont.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.base)
                            .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                        interactive: true)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                } else {
                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 8) {
                            if isGenerating { ProgressView().scaleEffect(0.8) }
                            else { Image(systemName: "sparkles") }
                            Text("passport_generate")
                        }
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.base)
                        .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                    interactive: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
                    .padding(.horizontal, AppSpacing.xl)
                }
                Spacer().frame(height: 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .background(appBackground.ignoresSafeArea())
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium])
    }

    private func generate() {
        guard let property = propertyService.primary else { return }
        isGenerating = true
        HapticFeedback.impact(.light)
        // ImageRenderer is main-actor; yield once so the spinner paints first.
        Task { @MainActor in
            await Task.yield()
            pdfURL = PropertyPassport.generate(PropertyPassport.Input(
                property: property,
                tasks: taskService.tasks,
                documents: documentService.documents,
                records: financialService.records,
                appliances: applianceService.appliances,
                valuations: propertyValueService.entries,
                preferredCurrency: appSettings.preferredCurrency))
            isGenerating = false
            if pdfURL != nil { HapticFeedback.success() }
        }
    }
}
