import SwiftUI

// MARK: - "Year of Your Home" — the pride moment
//
// A story page synthesized from the household's own year: photos captured,
// tasks finished, documents filed, money spent, the first memory and the
// busiest month — closed by a share card rendered on-device. Nothing here
// is generic; every number comes from this property's data, so the page is
// different in every home and gets richer the more the app is lived in.

struct YearInReviewView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(FinancialService.self) private var financialService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(DocumentService.self) private var documentService
    @Environment(AppSettings.self) private var appSettings

    @State private var shareImage: Image?

    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private var yearPrefix: String { "\(year)-" }

    // MARK: Synthesized numbers (all from this home's data)

    private var photosThisYear: [PhotoJournalEntry] {
        photoJournalService.entries.filter { $0.takenAt.hasPrefix(yearPrefix) }
    }
    private var tasksCompletedThisYear: [MaintenanceTask] {
        taskService.tasks.filter { $0.isCompleted && $0.updatedAt.hasPrefix(yearPrefix) }
    }
    private var documentsThisYear: Int {
        documentService.documents.filter { $0.createdAt.hasPrefix(yearPrefix) }.count
    }
    private var expensesThisYear: Double {
        financialService.records
            .filter { $0.type == "expense" && $0.date.hasPrefix(yearPrefix) }
            .reduce(0) { $0 + $1.amount }
    }
    private var biggestExpense: FinancialRecord? {
        financialService.records
            .filter { $0.type == "expense" && $0.date.hasPrefix(yearPrefix) }
            .max { $0.amount < $1.amount }
    }
    private var firstMemory: PhotoJournalEntry? {
        photosThisYear.min { $0.takenAt < $1.takenAt }
    }
    /// "yyyy-MM" of the month with the most completed tasks.
    private var busiestMonth: (key: String, count: Int)? {
        var byMonth: [String: Int] = [:]
        for t in tasksCompletedThisYear {
            byMonth[String(t.updatedAt.prefix(7)), default: 0] += 1
        }
        guard let best = byMonth.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                heroHeader
                statGrid
                storySection
                shareSection
                Spacer(minLength: 90)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Year of Your Home")
        .navigationBarTitleDisplayMode(.inline)
        .task { await renderShareCard() }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let ui = UIImage(named: "aerial_property") {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color.brandPurple, Color.brandPrimaryBlue],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(height: 180)
            .clipped()
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(year)")
                    .font(AppFont.scaled(34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(propertyService.primary?.name ?? "")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(AppSpacing.base)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 5)
    }

    // MARK: - Numbers

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            yearStat(value: "\(photosThisYear.count)", label: "Photos captured",
                     icon: "photo.stack.fill", color: .orange)
            yearStat(value: "\(tasksCompletedThisYear.count)", label: "Tasks completed",
                     icon: "checkmark.seal.fill", color: Color.brandSuccess)
            yearStat(value: "\(documentsThisYear)", label: "Documents filed",
                     icon: "doc.text.fill", color: Color.brandSkyBlue)
            yearStat(value: expenseDisplay, label: "Spent on the home",
                     icon: "banknote.fill", color: Color.brandPurple)
        }
    }

    private var expenseDisplay: String {
        financialService.moneyDisplay(expensesThisYear)
    }

    private func yearStat(value: String, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(AppFont.headline)
                .foregroundStyle(color)
            Text(value)
                .font(AppFont.scaled(26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.base)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            .strokeBorder(color.opacity(0.15), lineWidth: 0.8))
    }

    // MARK: - Story

    @ViewBuilder private var storySection: some View {
        if firstMemory != nil || busiestMonth != nil || biggestExpense != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("THE STORY")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .padding(.leading, AppSpacing.xxs)
                VStack(spacing: 0) {
                    if let first = firstMemory {
                        storyRow(icon: "sparkles", color: .orange,
                                 title: "First memory of the year",
                                 detail: first.title.isEmpty ? monthName(String(first.takenAt.prefix(7))) : first.title,
                                 thumb: URL(string: first.photoUrl))
                    }
                    if let busy = busiestMonth {
                        storyRow(icon: "flame.fill", color: Color.brandDanger,
                                 title: "Busiest month",
                                 detail: String(format: String(localized: "%@ — %d tasks done"),
                                                monthName(busy.key), busy.count))
                    }
                    if let big = biggestExpense {
                        storyRow(icon: "creditcard.fill", color: Color.brandPurple,
                                 title: "Biggest investment",
                                 detail: "\(big.title) · \(big.amountDisplay)")
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
            }
        }
    }

    private func storyRow(icon: String, color: Color, title: LocalizedStringKey,
                          detail: String, thumb: URL? = nil) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.subheadline).foregroundStyle(.primary)
                Text(detail)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
            }
            Spacer()
            if let thumb {
                StorageImage(url: thumb) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Color.primary.opacity(0.06) }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
    }

    private func monthName(_ yyyyMM: String) -> String {
        guard let d = AppDate.monthKey.date(from: yyyyMM) else { return yyyyMM }
        let out = DateFormatter(); out.dateFormat = "LLLL"
        out.locale = appSettings.appLocale
        return out.string(from: d).capitalized
    }

    // MARK: - Share

    @ViewBuilder private var shareSection: some View {
        if let shareImage {
            ShareLink(
                item: shareImage,
                preview: SharePreview(Text("Year of Your Home"), image: shareImage)
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(AppFont.subheadline)
                    Text("Share your year")
                        .font(AppFont.subheadline)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .mediaGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
        }
    }

    /// Renders the share card off-screen once the data is on hand.
    @MainActor
    private func renderShareCard() async {
        let card = YearShareCard(
            year: year,
            propertyName: propertyService.primary?.name ?? "PRVIO",
            photos: photosThisYear.count,
            tasksDone: tasksCompletedThisYear.count,
            documents: documentsThisYear,
            spent: expenseDisplay
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
        }
    }
}

// MARK: - The shareable card (fixed-size, rendered to an image)

private struct YearShareCard: View {
    let year: Int
    let propertyName: String
    let photos: Int
    let tasksDone: Int
    let documents: Int
    let spent: String

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 2) {
                Text(verbatim: "\(year)")
                    .font(AppFont.scaled(44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(propertyName)
                    .font(AppFont.headline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                cardStat("\(photos)", "Photos captured")
                cardStat("\(tasksDone)", "Tasks completed")
                cardStat("\(documents)", "Documents filed")
                cardStat(spent, "Spent on the home")
            }
            .padding(.horizontal, 28)

            Spacer()

            Text(verbatim: "PRVIO")
                .font(AppFont.scaled(13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.bottom, 20)
        }
        .frame(width: 340, height: 460)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.12, blue: 0.28),
                                    Color(red: 0.05, green: 0.16, blue: 0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func cardStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        HStack {
            Text(label)
                .font(AppFont.scaled(14))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            Text(value)
                .font(AppFont.scaled(20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
