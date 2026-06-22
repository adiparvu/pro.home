import SwiftUI

// MARK: - SeasonalChecklistView

struct SeasonalChecklistView: View {
    @StateObject var service = SeasonalChecklistService()
    @State var selectedSeason: Season = .current

    private var allItems: [SeasonalCheckItem] {
        SeasonalChecklistData.allItems.filter { $0.season == selectedSeason }
    }

    private var completedCount: Int {
        allItems.filter { service.isCompleted($0.id) }.count
    }

    private var totalCount: Int { allItems.count }

    private var isAllDone: Bool { totalCount > 0 && completedCount == totalCount }

    private var groupedItems: [String: [SeasonalCheckItem]] {
        Dictionary(grouping: allItems, by: \.category)
    }

    private var sortedCategories: [String] {
        groupedItems.keys.sorted()
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    seasonPicker
                    progressCard
                    if isAllDone {
                        allDoneBanner
                    }
                    checklistContent
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Seasonal Checklists")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Season Picker

    private var seasonPicker: some View {
        GlassCard(padding: 10) {
            HStack(spacing: 6) {
                ForEach([Season.spring, .summer, .fall, .winter], id: \.self) { season in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedSeason = season
                        }
                        HapticFeedback.impact(.light)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: season.icon)
                                .font(.system(size: 20))
                            Text(season.displayName)
                                .font(.system(size: 11, weight: selectedSeason == season ? .semibold : .regular))
                                .foregroundStyle(selectedSeason == season ? .white : Color.primary.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedSeason == season ? season.color : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 5)
                        .frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: totalCount > 0 ? CGFloat(completedCount) / CGFloat(totalCount) : 0)
                        .stroke(selectedSeason.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 52, height: 52)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: completedCount)
                    Text("\(totalCount > 0 ? Int(CGFloat(completedCount) / CGFloat(totalCount) * 100) : 0)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(completedCount) of \(totalCount) done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("\(selectedSeason.displayName) maintenance checklist")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.5))
                }

                Spacer()
            }
        }
    }

    // MARK: - All Done Banner

    private var allDoneBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Text("🎉")
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text("All done!")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Your \(selectedSeason.displayName.lowercased()) checklist is complete.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
                Spacer()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(selectedSeason.color.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Checklist

    private var checklistContent: some View {
        LazyVStack(spacing: 16) {
            ForEach(sortedCategories, id: \.self) { category in
                categorySection(category: category, items: groupedItems[category] ?? [])
            }
        }
    }

    private func categorySection(category: String, items: [SeasonalCheckItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            GlassCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        checkItem(item)
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private func checkItem(_ item: SeasonalCheckItem) -> some View {
        let done = service.isCompleted(item.id)
        return Button {
            service.toggleItem(item.id)
            HapticFeedback.impact(done ? .light : .medium)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? selectedSeason.color : Color.primary.opacity(0.3))
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: done)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(done ? Color.primary.opacity(0.35) : .primary)
                        .strikethrough(done, color: Color.primary.opacity(0.35))
                        .animation(.easeInOut(duration: 0.2), value: done)

                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(done ? 0.25 : 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(done ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: done)
    }
}
