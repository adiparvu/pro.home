import SwiftUI

// MARK: - Glass popover picker (the app's one filter control)
//
// Replaces the horizontal chip rows (mode pickers, category filters) that
// ate a full row — or two — at the top of list pages. One compact glass
// capsule shows the CURRENT selection; tapping it opens a real popover
// (`presentationCompactAdaptation(.popover)` keeps it a popover on iPhone,
// where small detents would otherwise become a sheet) listing the options
// with icons, optional honest counts, and a checkmark on the selection.
//
// Generic over the option's value so every page keeps its own enum/string
// vocabulary; display is data (`GlassPickerOption`), never reflection.

struct GlassPickerOption<Value: Hashable>: Identifiable {
    let value: Value
    var icon: String? = nil
    let title: String
    /// Honest count badge (documents per category, running activities…);
    /// nil = no badge. Zero still renders — hiding it would lie.
    var count: Int? = nil

    var id: Value { value }
}

struct GlassPopoverPicker<Value: Hashable>: View {
    let options: [GlassPickerOption<Value>]
    @Binding var selection: Value
    /// VoiceOver name for the control itself ("Filter", "View mode").
    var accessibilityLabelKey: LocalizedStringKey = "filter_picker"

    @State private var isPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: GlassPickerOption<Value>? {
        options.first { $0.value == selection }
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            isPresented = true
        } label: {
            HStack(spacing: AppSpacing.xs) {
                if let icon = selected?.icon {
                    Image(systemName: icon)
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(verbatim: selected?.title ?? "")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let count = selected?.count {
                    Text(verbatim: "\(count)")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.scaled(9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm + 1)
            .liquidGlass(cornerRadius: AppRadius.md)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityLabel(Text(accessibilityLabelKey))
        .accessibilityValue(Text(verbatim: selected?.title ?? ""))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            optionList
                // Clean floating card, no anchor tail (IMG_8566).
                .background(PopoverArrowKiller())
                .presentationCompactAdaptation(.popover)
        }
    }

    private var optionList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options) { option in
                    Button {
                        HapticFeedback.selection()
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            selection = option.value
                        }
                        isPresented = false
                    } label: {
                        GlassPopoverRow(icon: option.icon, title: option.title,
                                        count: option.count,
                                        isSelected: option.value == selection)
                    }
                    .buttonStyle(.plain)
                    if option.id != options.last?.id {
                        Divider().padding(.leading, AppSpacing.lg)
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .frame(minWidth: 230, maxHeight: 380)
    }
}

// MARK: - Multi-select variant (category filters)

/// Same glass trigger + popover, but options TOGGLE membership in a set and
/// the popover stays up for multi-picking. The trigger states the truth:
/// "All" when everything is on, otherwise the active count.
struct GlassPopoverMultiPicker<Value: Hashable>: View {
    let options: [GlassPickerOption<Value>]
    @Binding var selection: Set<Value>
    /// Trigger title when every option is active.
    let allTitle: String
    var icon: String = "line.3.horizontal.decrease"
    var accessibilityLabelKey: LocalizedStringKey = "filter_picker"
    /// Called after every toggle (persistence hooks).
    var onChange: () -> Void = {}

    @State private var isPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var allActive: Bool { selection.count >= options.count }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            isPresented = true
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(verbatim: allActive
                     ? allTitle
                     : "\(allTitle) · \(selection.count)/\(options.count)")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.scaled(9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm + 1)
            .liquidGlass(cornerRadius: AppRadius.md)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityLabel(Text(accessibilityLabelKey))
        .accessibilityValue(Text(verbatim: "\(selection.count)/\(options.count)"))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options) { option in
                        Button {
                            HapticFeedback.selection()
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                                if selection.contains(option.value) {
                                    selection.remove(option.value)
                                } else {
                                    selection.insert(option.value)
                                }
                            }
                            onChange()
                        } label: {
                            GlassPopoverRow(icon: option.icon, title: option.title,
                                            count: option.count,
                                            isSelected: selection.contains(option.value))
                        }
                        .buttonStyle(.plain)
                        if option.id != options.last?.id {
                            Divider().padding(.leading, AppSpacing.lg)
                        }
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
            .frame(minWidth: 230, maxHeight: 380)
            // Clean floating card, no anchor tail (IMG_8566).
            .background(PopoverArrowKiller())
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Shared option row
//
// Internal (not private): GlassFilterButton's aggregated sections render
// the exact same row, so every filter option in the app looks identical.

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
