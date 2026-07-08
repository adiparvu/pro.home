import SwiftUI

// MARK: - Month of Your Home
//
// The monthly sibling of "Year of Your Home": what this month actually held —
// tasks closed, money spent (per currency, never mixed), photos taken,
// documents filed, and the house streak. Everything is computed from data
// already in memory; nothing is fetched and nothing is invented. The share
// card renders the same numbers into an image for the family chat.

struct MonthlyRecapView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(FinancialService.self) private var financialService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(DocumentService.self) private var documentService

    @State private var shareURL: URL? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                PageHeader(title: monthTitle, subtitleKey: "monthly_subtitle")
                heroCard
                statGrid
                spendingCard
                if SharedDataStore.currentHouseStreak() >= 2 {
                    streakCard
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(AppFont.headline)
                    }
                    .accessibilityLabel(Text("monthly_share_a11y"))
                }
            }
        }
        .onAppear(perform: renderShareCard)
    }

    // MARK: Facts (this calendar month, from loaded data)

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: Date()).capitalized
    }

    private var monthPrefix: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    /// Completed tasks whose last update landed this month — completion is
    /// the update that flips the status, so this is the honest available
    /// signal (the schema has no completed_at column).
    private var tasksCompleted: Int {
        taskService.tasks.filter { $0.isCompleted && $0.updatedAt.hasPrefix(monthPrefix) }.count
    }

    private var photosTaken: Int {
        photoJournalService.entries.filter { $0.takenAt.hasPrefix(monthPrefix) }.count
    }

    private var documentsAdded: Int {
        documentService.documents.filter { $0.createdAt.hasPrefix(monthPrefix) }.count
    }

    /// Expenses per currency, listed separately — never silently summed.
    private var spendingByCurrency: [(code: String, total: Double)] {
        let expenses = financialService.currentMonthRecords.filter { $0.type == "expense" }
        return Dictionary(grouping: expenses, by: \.currency)
            .map { (code: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    // MARK: Cards

    private var heroCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(AppFont.scaled(34))
                .foregroundStyle(.indigo)
                .symbolRenderingMode(.hierarchical)
            Text(verbatim: "\(tasksCompleted)")
                .font(AppFont.scaled(44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("monthly_tasks_done")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
            if let name = propertyService.primary?.name {
                Text(name)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private var statGrid: some View {
        HStack(spacing: 10) {
            statTile(icon: "camera.fill", tint: .pink,
                     value: photosTaken, label: "monthly_photos")
            statTile(icon: "doc.text.fill", tint: .orange,
                     value: documentsAdded, label: "monthly_documents")
        }
    }

    private func statTile(icon: String, tint: Color, value: Int, label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.headline)
                .foregroundStyle(tint)
            Text(verbatim: "\(value)")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    @ViewBuilder
    private var spendingCard: some View {
        if !spendingByCurrency.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "banknote.fill")
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.brandSuccess)
                    Text("monthly_spending")
                        .font(AppFont.footnoteEmphasis)
                    Spacer()
                }
                ForEach(spendingByCurrency, id: \.code) { entry in
                    HStack {
                        Text(entry.code)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(CurrencyService.money(entry.total, code: entry.code))
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    }
                }
            }
            .padding(AppSpacing.lg)
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    private var streakCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(AppFont.title3)
                .foregroundStyle(.orange)
            Text("monthly_streak \(SharedDataStore.currentHouseStreak())")
                .font(AppFont.footnoteEmphasis)
            Spacer()
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    // MARK: Share card

    /// A compact 1080×1350 card with the month's numbers, rendered off the
    /// live view so sharing never depends on scroll position.
    @MainActor
    private func renderShareCard() {
        let card = MonthlyShareCard(
            month: monthTitle,
            property: propertyService.primary?.name,
            tasks: tasksCompleted,
            photos: photosTaken,
            documents: documentsAdded,
            spending: spendingByCurrency.map { CurrencyService.money($0.total, code: $0.code) })
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRVIO-\(monthPrefix).png")
        if (try? data.write(to: url)) != nil {
            shareURL = url
        }
    }
}

// MARK: - Share card (rendered, not screenshotted)

private struct MonthlyShareCard: View {
    let month: String
    let property: String?
    let tasks: Int
    let photos: Int
    let documents: Int
    let spending: [String]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.stars.fill")
                .font(AppFont.scaled(44))
                .foregroundStyle(.white.opacity(0.9))
            Text(month)
                .font(AppFont.title)
                .foregroundStyle(.white)
            if let property {
                Text(property)
                    .font(AppFont.scaled(16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 26) {
                shareStat(value: tasks, label: String(localized: "monthly_tasks_done"))
                shareStat(value: photos, label: String(localized: "monthly_photos"))
                shareStat(value: documents, label: String(localized: "monthly_documents"))
            }
            .padding(.top, 6)
            ForEach(spending, id: \.self) { line in
                Text(line)
                    .font(AppFont.scaled(18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(verbatim: "PRVIO")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 8)
        }
        .frame(width: 540, height: 675)
        .background(
            LinearGradient(colors: [Color.indigo, Color(red: 0.10, green: 0.08, blue: 0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func shareStat(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: "\(value)")
                .font(AppFont.scaled(34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(AppFont.scaled(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
