import SwiftUI
import Charts
import PhotosUI

// MARK: - Property insights (expenses · gallery · value)
//
// Rich, data-driven sections at the bottom of the property page: a monthly
// expense chart, the property's photo gallery, and the value evolution — each
// a self-contained glass card that loads its own data for this property.

struct PropertyInsightsSections: View {
    let propertyId: UUID

    @State private var financial = FinancialService()
    @State private var photos = PhotoJournalService()
    @State private var values = PropertyValueService()
    @State private var fullscreenPhoto: PhotoJournalEntry?
    @State private var galleryPicks: [PhotosPickerItem] = []
    @State private var isUploadingGallery = false
    @State private var galleryError: String?

    var body: some View {
        VStack(spacing: 16) {
            expensesCard
            galleryCard
            valueCard
        }
        .task {
            async let a: Void = financial.load()
            async let b: Void = photos.load(propertyId: propertyId)
            async let c: Void = values.load(propertyId: propertyId)
            _ = await (a, b, c)
        }
        .fullScreenCover(item: $fullscreenPhoto) { entry in
            PhotoLightbox(entry: entry) { fullscreenPhoto = nil }
        }
    }

    // MARK: - Expenses

    private var expensesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Expenses", systemImage: "chart.bar.fill")
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Spacer()
                    if financial.currentMonthExpenses > 0 {
                        Text("\(amount(financial.currentMonthExpenses)) \(financial.currencySymbol)")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.brandDanger)
                        Text("this month")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }

                if financial.records.isEmpty {
                    emptyHint("No expenses recorded yet.")
                } else {
                    Chart(financial.monthlyData, id: \.month) { item in
                        BarMark(
                            x: .value("Month", item.month),
                            y: .value("Expenses", item.expenses)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [Color.brandDanger.opacity(0.85), Color.brandDanger.opacity(0.45)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .cornerRadius(4)
                        if item.income > 0 {
                            BarMark(
                                x: .value("Month", item.month),
                                y: .value("Income", item.income)
                            )
                            .foregroundStyle(
                                LinearGradient(colors: [Color.brandSuccess.opacity(0.85), Color.brandSuccess.opacity(0.45)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(4)
                            .position(by: .value("Kind", "income"))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { _ in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(AppOpacity.hairline))
                            AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.secondaryTextColor)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().font(.system(size: 10)).foregroundStyle(Color.secondaryTextColor)
                        }
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    // MARK: - Gallery

    private var galleryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Gallery", systemImage: "photo.on.rectangle.angled")
                        .font(AppFont.label)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    Spacer()
                    if !photos.entries.isEmpty {
                        Text("\(photos.entries.count)")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(photos.entries.prefix(12)) { entry in
                            Button { fullscreenPhoto = entry } label: {
                                AsyncImage(url: URL(string: entry.photoUrl)) { phase in
                                    if case .success(let img) = phase {
                                        img.resizable().scaledToFill()
                                    } else {
                                        Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                                            .overlay(ProgressView().controlSize(.small))
                                    }
                                }
                                .frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await photos.delete(entry) }
                                } label: {
                                    Label("Delete Photo", systemImage: "trash")
                                }
                            }
                        }
                        galleryAddTile
                    }
                }
                if photos.entries.isEmpty {
                    emptyHint("Add photos of your property — separate from the cover photo.")
                }
                if let galleryError {
                    Text(galleryError)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.brandDanger)
                }
            }
        }
        .onChange(of: galleryPicks) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await uploadGalleryPicks(newItems) }
        }
    }

    private var galleryAddTile: some View {
        PhotosPicker(selection: $galleryPicks, maxSelectionCount: 10, matching: .images) {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color.primary.opacity(AppOpacity.subtleFill))
                .frame(width: 92, height: 92)
                .overlay {
                    if isUploadingGallery {
                        ProgressView().controlSize(.small)
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .medium))
                            Text("Add")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.3),
                                      style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        }
        .disabled(isUploadingGallery)
        .accessibilityLabel("Add photos")
    }

    private func uploadGalleryPicks(_ items: [PhotosPickerItem]) async {
        isUploadingGallery = true
        galleryError = nil
        defer {
            isUploadingGallery = false
            galleryPicks = []
        }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            do {
                try await photos.upload(imageData: data, propertyId: propertyId)
            } catch {
                galleryError = String(format: String(localized: "Upload failed: %@"),
                                      error.localizedDescription)
                HapticFeedback.warning()
                return
            }
        }
        HapticFeedback.success()
    }

    // MARK: - Value

    private var sortedValues: [PropertyValueEntry] {
        values.entries.sorted { ($0.enteredDate ?? .distantPast) < ($1.enteredDate ?? .distantPast) }
    }

    private var valueCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Property value", systemImage: "chart.line.uptrend.xyaxis")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                if sortedValues.isEmpty {
                    emptyHint("Add value estimates to follow how your property appreciates.")
                } else {
                    let latest = sortedValues[sortedValues.count - 1]
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        Text("\(amount(latest.valueAmount)) \(latest.currency)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        if sortedValues.count >= 2 {
                            let prev = sortedValues[sortedValues.count - 2].valueAmount
                            let delta = prev == 0 ? 0 : (latest.valueAmount - prev) / prev * 100
                            HStack(spacing: 3) {
                                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                Text(String(format: "%+.1f%%", delta))
                            }
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(delta >= 0 ? Color.brandSuccess : Color.brandDanger)
                        }
                        Spacer()
                    }

                    if sortedValues.count >= 2 {
                        Chart(sortedValues) { entry in
                            AreaMark(
                                x: .value("Date", entry.enteredDate ?? Date()),
                                y: .value("Value", entry.valueAmount)
                            )
                            .foregroundStyle(
                                LinearGradient(colors: [Color.brandPrimaryBlue.opacity(0.35), .clear],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .interpolationMethod(.monotone)
                            LineMark(
                                x: .value("Date", entry.enteredDate ?? Date()),
                                y: .value("Value", entry.valueAmount)
                            )
                            .foregroundStyle(Color.brandPrimaryBlue)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                        }
                        .chartYAxis {
                            AxisMarks(position: .trailing) { _ in
                                AxisGridLine().foregroundStyle(Color.primary.opacity(AppOpacity.hairline))
                                AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.secondaryTextColor)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                                    .font(.system(size: 10)).foregroundStyle(Color.secondaryTextColor)
                            }
                        }
                        .frame(height: 130)
                    }

                    if let source = latest.source, !source.isEmpty {
                        Text(String(format: String(localized: "Latest estimate: %@"), source))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func emptyHint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.footnote)
            .foregroundStyle(Color.secondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.xs)
    }

    private func amount(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
}

// MARK: - Fullscreen photo viewer

private struct PhotoLightbox: View {
    let entry: PhotoJournalEntry
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: URL(string: entry.photoUrl)) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(AppFont.headline)
                    .foregroundStyle(.white)
                    .padding(AppSpacing.md)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(AppSpacing.xl)
            .accessibilityLabel("Close")
        }
    }
}
