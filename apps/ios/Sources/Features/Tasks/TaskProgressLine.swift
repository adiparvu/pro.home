import SwiftUI

// MARK: - Task progress card
//
// The day's status as a single glass card (IMG_8311): a large ring showing
// "% completed" beside "X of Y done" with a slim progress bar, then a divider
// and three stat columns — Întârziate / În progres / Finalizate. Those columns
// double as the list's ONE filter: tapping a column selects that filter and
// tinting/underline marks it; tapping again clears back to everything. All
// counts roll with `.numericText()`.
//
// The public shape is unchanged (doneToday / plateToday / chips), so the
// call-site is untouched.

struct TaskProgressLine: View {
    let doneToday: Int
    let plateToday: Int
    let chips: [Chip]

    struct Chip: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let count: Int
        let tint: Color
        let isSelected: Bool
        let action: () -> Void
    }

    private var progress: Double {
        plateToday > 0 ? Double(doneToday) / Double(plateToday) : 0
    }
    private var percent: Int { Int((progress * 100).rounded()) }
    private var countText: String {
        String(format: String(localized: "task_progress_count_format"), doneToday, plateToday)
    }

    var body: some View {
        VStack(spacing: AppSpacing.base) {
            topRow
            Divider().overlay(Color.primary.opacity(AppOpacity.hairline))
            statsRow
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5)
        )
    }

    // MARK: - Ring + "X of Y done"

    private var topRow: some View {
        HStack(spacing: AppSpacing.lg) {
            ring
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Color.brandSkyBlue).frame(width: 8, height: 8)
                    Text("task_progress_today_label")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color.brandSkyBlue)
                }
                Text(countText)
                    .font(AppFont.scaled(30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.taskSpring, value: doneToday)
                Text("task_progress_finalized_sub")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.secondaryTextColor)
                progressBar.padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("task_progress_today_label"))
        .accessibilityValue(Text(verbatim: "\(percent)% — \(countText)"))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.brandSuccess, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.taskSpring, value: progress)
            VStack(spacing: 0) {
                Text(verbatim: "\(percent)%")
                    .font(AppFont.scaled(26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.taskSpring, value: percent)
                Text("task_progress_completed_pct")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.secondaryTextColor)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityHidden(true)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(Color.brandSuccess)
                    .frame(width: max(0, geo.size.width * progress))
                    .animation(.taskSpring, value: progress)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Stat columns (the list filter)

    private var statsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { idx, chip in
                if idx > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(AppOpacity.hairline))
                        .frame(width: 0.5, height: 34)
                }
                statColumn(chip)
            }
        }
    }

    private func statColumn(_ chip: Chip) -> some View {
        Button {
            HapticFeedback.selection()
            chip.action()
        } label: {
            VStack(spacing: 3) {
                Text(verbatim: "\(chip.count)")
                    .font(AppFont.scaled(24, weight: .bold, design: .rounded))
                    .foregroundStyle(chip.tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.taskSpring, value: chip.count)
                Text(chip.label)
                    .font(AppFont.footnote)
                    .foregroundStyle(chip.isSelected ? chip.tint : Color.secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(chip.isSelected ? chip.tint.opacity(AppOpacity.tintedFill) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chip.label)
        .accessibilityValue(Text(verbatim: "\(chip.count)"))
        .accessibilityAddTraits(chip.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
