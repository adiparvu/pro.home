import SwiftUI

// MARK: - Stat card
//
// One of the four Liquid-Glass summary tiles at the top of the Tasks screen
// (Toate / În progres / Întârziate / Finalizate). The count rolls with a
// numeric-text content transition, and the selected tile carries an accent
// underline — tapping a tile drives the list's active filter.

struct TaskStatCard: View {
    let icon: String
    let tint: Color
    let value: Int
    let label: LocalizedStringKey
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(AppOpacity.tintedFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("\(value)")
                        .font(AppFont.title2)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .animation(.taskSpring, value: value)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(AppFont.scaled(13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Capsule()
                        .fill(isSelected ? tint : Color.clear)
                        .frame(width: 26, height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.base)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(isSelected ? tint.opacity(0.35) : Color.primary.opacity(AppOpacity.hairline),
                                  lineWidth: isSelected ? 1 : 0.5)
            )
            .shadow(color: Color.primary.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
