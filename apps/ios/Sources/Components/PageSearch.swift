import SwiftUI

// MARK: - Page search (system search field)
//
// The uniform search pattern for list pages is the plain system field —
// no toggle button. One @State per page:
//
//   @State private var searchText = ""
//
//   .searchable(text: $searchText,
//               placement: .navigationBarDrawer(displayMode: .automatic))
//
// Large-title pages use .automatic: the title arrives LARGE on entry and a
// pull-down reveals the field — the system pattern (Mail, Notes). A pinned
// .always drawer keeps the bar collapsed on entry (IMG_8070), so it's right
// only for inline-title picker sheets that are search-first. The earlier
// title flash blamed on .automatic came from the removed zoom transitions.
// Filter the displayed collection with `matchesSearch`. (The inline
// `SearchIconButton`/`PageSearchField` pair that once served the Digital
// Twin's floating overlay is gone — every surface now uses the system field.)

extension String {
    /// Case- and diacritic-insensitive match used by page search filters.
    func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
