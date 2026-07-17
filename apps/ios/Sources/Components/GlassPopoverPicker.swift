import SwiftUI

// MARK: - Glass picker vocabulary (option model + shared row)
//
// The standalone capsule pickers that once lived here were superseded by the
// one-circle law: every page now aggregates its filters behind ONE
// GlassFilterButton (Components/GlassFilterButton.swift). What remains is the
// shared vocabulary those sections speak:
//   • `GlassPickerOption` — the data an option carries (value, icon, title,
//     honest count). Display is data, never reflection.
//   • `GlassPopoverRow`   — the one row every filter option renders as, so an
//     option looks identical wherever it appears.

struct GlassPickerOption<Value: Hashable>: Identifiable {
    let value: Value
    var icon: String? = nil
    let title: String
    /// Honest count badge (documents per category, running activities…);
    /// nil = no badge. Zero still renders — hiding it would lie.
    var count: Int? = nil

    var id: Value { value }
}

// MARK: - Shared option row
//
// GlassFilterButton's aggregated sections render the exact same row, so
// every filter option in the app looks identical.

struct GlassPopoverRow: View {
    let icon: String?
    let title: String
    let count: Int?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
            }
            Text(verbatim: title)
                .font(AppFont.scaled(15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: AppSpacing.lg)
            if let count {
                Text(verbatim: "\(count)")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Image(systemName: "checkmark")
                .font(AppFont.scaled(12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }
}
