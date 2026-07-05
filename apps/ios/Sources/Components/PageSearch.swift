import SwiftUI

// MARK: - Page search (magnifier toggle + inline field)
//
// The uniform search pattern for list pages: a magnifier button in the
// page's header/toolbar toggles an inline search field that filters the
// page content live. Keep one @State pair per page:
//
//   @State private var showSearch = false
//   @State private var searchText = ""
//
//   SearchIconButton(isActive: $showSearch)          // header/toolbar
//   if showSearch { PageSearchField(text: $searchText) }
//
// and filter the displayed collection with `matchesSearch`.

struct SearchIconButton: View {
    @Binding var isActive: Bool
    /// Plain style matches toolbar icon rows; glass style matches custom
    /// headers built from round glass buttons.
    var style: Style = .toolbar

    enum Style { case toolbar, glass }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            withAnimation(.snappy(duration: 0.25)) { isActive.toggle() }
        } label: {
            switch style {
            case .toolbar:
                Image(systemName: "magnifyingglass")
                    .font(AppFont.subheadline)
                    .foregroundStyle(isActive ? Color.accentColor : .primary)
                    .frame(width: 38, height: 32)
            case .glass:
                Image(systemName: "magnifyingglass")
                    .font(AppFont.headline)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .glassCircle()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
    }
}

struct PageSearchField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey = "Search…"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 14)
        .onAppear { focused = true }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension String {
    /// Case- and diacritic-insensitive match used by page search filters.
    func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
