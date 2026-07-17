import SwiftUI
import UIKit

// MARK: - Arrowless popovers (IMG_8566)
//
// SwiftUI's `.popover` always draws the UIKit anchor arrow; the app's menus
// must present as clean floating glass cards with no tail — the native
// iOS 26 Menu look. SwiftUI has no public switch, but the presentation is
// backed by `UIPopoverPresentationController`, whose `permittedArrowDirections`
// is public API. This helper rides inside the popover content, finds its own
// hosting controller through the responder chain the moment the view joins
// the window (early in the presentation transition, before final layout),
// and turns the arrow off.

private final class PopoverArrowKillerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        var responder: UIResponder? = self
        while let current = responder {
            if let vc = current as? UIViewController {
                vc.popoverPresentationController?.permittedArrowDirections = []
                break
            }
            responder = current.next
        }
    }
}

struct PopoverArrowKiller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { PopoverArrowKillerView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - GlassFilterButton — one circle, every filter (IMG_8540)
//
// The page-level consolidation of filters: ONE circular Liquid Glass button
// that opens a single popover hosting EVERY view option and filter the page
// has — view modes, categories, periods, sort — instead of a permanent row
// of chips or one capsule per picker. The popover composes the sections
// below; each renders the same `GlassPopoverRow` the capsule pickers use,
// so an option looks identical wherever it appears.
//
// Placement contract: standalone (in-body headers) draws its own glass
// circle; `inToolbar: true` skips it, because iOS 26 wraps toolbar controls
// in system glass and a manual circle would double-draw.
//
// The trigger never lies about state: `isActive` (any hosted filter away
// from its default) shows a small accent dot — the page computes it from
// its own state, honestly, or omits it.

/// Popover-scoped mailbox for one-shot actions (share, print, navigate):
/// a row deposits its work here and closes the popover; the button runs it
/// from the content's `onDisappear` — i.e. AFTER the dismissal transition —
/// so a share sheet or print panel never races the dying presentation.
/// (The previous fixed 350ms guess lost that race on device: UIKit dropped
/// the presentation silently and the rows "did nothing" — IMG_8560.)
final class GlassPopoverActionMailbox {
    var pending: (() -> Void)?
}

private struct GlassPopoverMailboxKey: EnvironmentKey {
    static let defaultValue: GlassPopoverActionMailbox? = nil
}

extension EnvironmentValues {
    var glassPopoverMailbox: GlassPopoverActionMailbox? {
        get { self[GlassPopoverMailboxKey.self] }
        set { self[GlassPopoverMailboxKey.self] = newValue }
    }
}

struct GlassFilterButton<Content: View>: View {
    /// Accent dot when any hosted filter is narrowed from its default.
    var isActive: Bool = false
    /// True when placed in a `.toolbar` — the system supplies the glass.
    var inToolbar: Bool = false
    /// Trigger glyph. The filter lines by default; pages that host quick
    /// NAVIGATION rows instead of filters pass Apple's More glyph
    /// ("ellipsis") so the icon never lies about what's inside.
    var icon: String = "line.3.horizontal.decrease"
    var accessibilityLabelKey: LocalizedStringKey = "filter_picker"
    /// Standalone trigger diameter — headers whose round actions use a
    /// larger circle (the chat header's 44pt) pass theirs so the trigger
    /// sits flush with its siblings. Ignored in toolbars (system metrics).
    var standaloneSize: CGFloat = 38
    @ViewBuilder var content: () -> Content

    @State private var isPresented = false
    @State private var mailbox = GlassPopoverActionMailbox()
    /// Content's measured height. Once known, the popover height is FIXED
    /// (never re-derived from the scroll's ideal size), because a popover
    /// that keeps re-measuring a scrolling ScrollView re-anchors on every
    /// frame and the whole page appears to jump under it (IMG_8561).
    @State private var contentHeight: CGFloat?

    private static var maxPopoverHeight: CGFloat { 440 }

    /// Glyph tracks the circle (15pt at the 38pt default) so a larger
    /// standalone trigger doesn't render a visibly under-weight icon.
    private var glyphSize: CGFloat {
        inToolbar ? 15 : (standaloneSize * 15 / 38).rounded()
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            isPresented = true
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(glyphSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: inToolbar ? 28 : standaloneSize,
                       height: inToolbar ? 28 : standaloneSize)
                .overlay(alignment: .topTrailing) {
                    if isActive {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: inToolbar ? 1 : -5, y: inToolbar ? 1 : 5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(StandaloneGlassCircle(enabled: !inToolbar))
        .accessibilityLabel(Text(accessibilityLabelKey))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.vertical, AppSpacing.xs)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                }
            }
            .frame(minWidth: 250)
            .frame(height: contentHeight.map { min($0, Self.maxPopoverHeight) })
            .frame(maxHeight: contentHeight == nil ? Self.maxPopoverHeight : nil)
            .scrollBounceBehavior(.basedOnSize)
            .background(PopoverArrowKiller())
            .environment(\.glassPopoverMailbox, mailbox)
            .onDisappear {
                // The popover is gone — presentation is safe again. The short
                // hop lets UIKit finish tearing the hosting controller down.
                guard let action = mailbox.pending else { return }
                mailbox.pending = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    action()
                }
            }
            .presentationCompactAdaptation(.popover)
        }
    }
}

private struct StandaloneGlassCircle: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.glassCircle()
        } else {
            content
        }
    }
}

// MARK: - Popover building blocks
//
// Sections deliberately do NOT dismiss the popover on selection: the whole
// point of the aggregate is adjusting several filters in one visit. The
// user closes it by tapping away — the standard popover gesture.

/// Uppercase section label separating filter groups inside the popover.
struct GlassFilterSectionLabel: View {
    let titleKey: LocalizedStringKey

    var body: some View {
        Text(titleKey)
            .textCase(.uppercase)
            .font(AppFont.label)
            .kerning(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Hairline between two sections.
struct GlassFilterSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.top, AppSpacing.sm)
    }
}

/// Single-select group: exactly one value active, checkmarked.
struct GlassFilterSection<Value: Hashable>: View {
    var title: LocalizedStringKey? = nil
    let options: [GlassPickerOption<Value>]
    @Binding var selection: Value
    /// Persistence/side-effect hook, fired after every change.
    var onChange: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { GlassFilterSectionLabel(titleKey: title) }
            ForEach(options) { option in
                Button {
                    HapticFeedback.selection()
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        selection = option.value
                    }
                    onChange()
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
    }
}

/// Multi-select group: options toggle membership in a set.
struct GlassFilterMultiSection<Value: Hashable>: View {
    var title: LocalizedStringKey? = nil
    let options: [GlassPickerOption<Value>]
    @Binding var selection: Set<Value>
    var onChange: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { GlassFilterSectionLabel(titleKey: title) }
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
    }
}

/// One ACTION row (share, export, print…) — unlike the filter rows it is
/// one-shot: it closes the popover, then runs the action once the popover
/// is gone (a share sheet presented while the popover is still dismissing
/// would lose the presentation race). No checkmark — actions have no state.
struct GlassFilterActionRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.glassPopoverMailbox) private var mailbox

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            if let mailbox {
                // Deterministic: the popover's onDisappear runs this once the
                // dismissal transition is truly over (IMG_8560).
                mailbox.pending = action
                dismiss()
            } else {
                // Outside a GlassFilterButton popover — best-effort delay.
                dismiss()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    action()
                }
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(AppFont.scaled(14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                Text(verbatim: title)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.lg)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One boolean row (e.g. "Favorites only") — checkmark mirrors the toggle.
struct GlassFilterToggleRow: View {
    var icon: String? = nil
    let title: String
    @Binding var isOn: Bool
    var onChange: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticFeedback.selection()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                isOn.toggle()
            }
            onChange()
        } label: {
            GlassPopoverRow(icon: icon, title: title, count: nil, isSelected: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
