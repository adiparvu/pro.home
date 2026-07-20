import SwiftUI

// MARK: - Page search (system search field)
//
// The uniform search pattern for list pages is the plain system field —
// no toggle button, DEFAULT placement. One @State per page:
//
//   @State private var searchText = ""
//
//   .searchable(text: $searchText, prompt: Text("Search…"))
//
// Default placement is the current cycle's search: on iPhone the system
// hosts the field bottom-aligned (iOS 26's reachability redesign — Apple's
// own apps moved there), and it keeps working on newer OS builds where the
// legacy `navigationBarDrawer(displayMode: .automatic)` drawer stopped
// propagating its text binding (typing filtered nothing — the "căutarea nu
// funcționează" report). A pinned `.navigationBarDrawer(displayMode:
// .always)` remains right ONLY for inline-title picker sheets that are
// search-first. Filter the displayed collection with `matchesSearch`.

extension String {
    /// Case- and diacritic-insensitive match used by page search filters.
    func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
