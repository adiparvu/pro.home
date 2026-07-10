import SwiftUI

// MARK: - Progress line
//
// The slim replacement for the four stat tiles: one glass row holding a
// small progress ring, "X din Y azi" (completed today / on today's plate),
// and three count chips — Întârziate / În progres / Finalizate — that drive
// the list's ONE filter state. A selected chip fills with its accent; tapping
// it again clears back to everything. Counts roll with `.numericText()`.
//
// `ViewThatFits` keeps it a single line normally and gracefully stacks the
// chips beneath the ring at large Dynamic Type sizes instead of truncating.

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

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.md) {
                ringAndLabel
                Spacer(minLength: AppSpacing.sm)
                chipRow
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ringAndLabel
                chipRow
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5)
        )
    }

    // MARK: - Ring + "X din Y azi"

    private var ringAndLabel: some View {
        HStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.brandSuccess, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.taskSpring, value: progress)
            }
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            Text("task_progress_today \(doneToday) \(plateToday)")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.taskSpring, value: doneToday)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Filter chips

    private var chipRow: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(chips) { chip in
                chipView(chip)
            }
        }
    }

    private func chipView(_ chip: Chip) -> some View {
        Button {
            HapticFeedback.selection()
            chip.action()
        } label: {
            HStack(spacing: 4) {
                Text(chip.label)
                    .font(AppFont.scaled(12, weight: chip.isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(verbatim: "\(chip.count)")
                    .font(AppFont.scaled(12, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.taskSpring, value: chip.count)
            }
            .foregroundStyle(chip.isSelected ? Color.white : chip.tint)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(chip.isSelected ? chip.tint : chip.tint.opacity(AppOpacity.tintedFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chip.label)
        .accessibilityValue(Text(verbatim: "\(chip.count)"))
        .accessibilityAddTraits(chip.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
