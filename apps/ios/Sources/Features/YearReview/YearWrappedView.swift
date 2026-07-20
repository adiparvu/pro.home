import SwiftUI

// MARK: - „Vezi povestea" — the year as a full-screen story
//
// A paged, immersive presentation of the year's real numbers: cover → one
// big number per page → a closing card. Pages are built by the recap page
// exclusively from data that exists (honesty law), so an empty chapter never
// becomes an empty slide. Motion: `.smooth` auto-advance and a gentle number
// entrance — both disabled under Reduce Motion, where the story becomes
// plain manual paging. Swipe down (or the close button) dismisses.

// MARK: - Page model

struct YearWrappedPage: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    /// The big number / amount, already formatted (verbatim).
    let value: String
    let label: LocalizedStringKey
    /// Optional secondary line (a task title, a member name…), verbatim.
    var detail: String?
}

// MARK: - The story container

struct YearWrappedView: View {
    let year: Int
    let propertyName: String
    let pages: [YearWrappedPage]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageIndex = 0
    @State private var dragOffset: CGFloat = 0

    private var lastIndex: Int { pages.count + 1 }

    var body: some View {
        ZStack {
            AppBackdrop(fixed: .night)
                .ignoresSafeArea()
            pageTint
                .ignoresSafeArea()

            TabView(selection: $pageIndex) {
                coverPage.tag(0)
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    YearWrappedStatPage(page: page).tag(index + 1)
                }
                closingPage.tag(lastIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .indexViewStyle(.page(backgroundDisplayMode: .never))

            closeButton
        }
        .environment(\.colorScheme, .dark)
        .offset(y: max(0, dragOffset))
        .gesture(dismissDrag)
        .task(id: pageIndex) { await autoAdvance() }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: pageIndex)
    }

    /// A quiet radial accent in the current page's tint over the night
    /// ground — the "mood" of each number, at palette-level opacity.
    private var pageTint: some View {
        let tint: Color = {
            guard pageIndex >= 1, pageIndex <= pages.count else { return Color.brandPurple }
            return pages[pageIndex - 1].tint
        }()
        return RadialGradient(colors: [tint.opacity(0.16), .clear],
                              center: UnitPoint(x: 0.5, y: 0.28),
                              startRadius: 0, endRadius: 420)
            .animation(reduceMotion ? nil : .smooth(duration: 0.8), value: pageIndex)
    }

    // MARK: Auto-advance (never under Reduce Motion)

    private func autoAdvance() async {
        guard !reduceMotion, pageIndex < lastIndex else { return }
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled, pageIndex < lastIndex else { return }
        withAnimation(.smooth(duration: 0.5)) { pageIndex += 1 }
    }

    // MARK: Dismissal

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 25)
            .onChanged { value in
                if value.translation.height > 0,
                   abs(value.translation.height) > abs(value.translation.width) {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 110 {
                    dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    HapticFeedback.impact(.light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                }
                .glassCircle()
                .accessibilityLabel(Text("year_wrapped_close_a11y"))
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
    }

    // MARK: Cover

    private var coverPage: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles")
                .font(AppFont.scaled(40))
                .foregroundStyle(Color.brandGold)
                .symbolRenderingMode(.hierarchical)
            Text(verbatim: "\(year)")
                .font(AppFont.scaled(76, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text("year_wrapped_title")
                .font(AppFont.title3)
                .foregroundStyle(.primary)
            Text(verbatim: propertyName)
                .font(AppFont.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("year_wrapped_hint")
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.bottom, 54)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.xxl)
        .accessibilityElement(children: .combine)
    }

    // MARK: Closing card

    private var closingPage: some View {
        VStack(spacing: 16) {
            Spacer()
            PRVIOLogoView(size: 56)
            Text("year_wrapped_outro")
                .font(AppFont.title3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(verbatim: "\(propertyName) · \(year)")
                .font(AppFont.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("year_wrapped_made_with")
                .font(AppFont.scaled(12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.bottom, 54)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.xxl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - One big-number page

private struct YearWrappedStatPage: View {
    let page: YearWrappedPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: page.icon)
                .font(AppFont.scaled(34))
                .foregroundStyle(page.tint)
                .symbolRenderingMode(.hierarchical)
            Text(verbatim: page.value)
                .font(AppFont.scaled(64, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .scaleEffect(reduceMotion || revealed ? 1 : 0.86)
                .opacity(reduceMotion || revealed ? 1 : 0)
            Text(page.label)
                .font(AppFont.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detail = page.detail {
                Text(verbatim: detail)
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Spacer()
            Spacer().frame(height: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.xxl)
        .accessibilityElement(children: .combine)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.smooth(duration: 0.55)) { revealed = true }
        }
        .onDisappear { revealed = false }
    }
}
