import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct DocumentsView: View {
    @Environment(DocumentService.self) private var documentService
    @Environment(PropertyService.self) private var propertyService
    @State private var search = ""
    @State private var selectedCategory: String? = nil
    @State private var showAdd = false
    @State private var docToDelete: DocumentModel?
    @State private var showDeleteConfirm = false
    @State private var previewURL: URL?
    @State private var errorToast: String?
    @State private var sharePayload: SharePayload?
    @State private var selectedDoc: DocumentModel?
    @State private var editDoc: DocumentModel?
    // Bumped when a favorite toggles so the (UserDefaults-backed) filter/badges refresh.
    @State private var favRefresh = 0
    @State private var showReview = false
    // Scan as a first-rank action: the header scanner feeds its result into
    // the add sheet, so a scanned paper arrives with PDF + OCR prefill set.
    @State private var showScanner = false
    @State private var pendingScan: DocumentScanResult?

    private let categories = ["All", "Favorite", "warranty", "contract", "legal", "insurance",
                               "certificate", "manual", "invoice", "permit", "tax", "utility",
                               "photo", "other"]

    enum DocSort: String {
        case recent, name, expiry
    }

    @State private var sortOrder: DocSort = .recent

    private func filtered(favs: Set<String>) -> [DocumentModel] {
        var docs = documentService.documents
        switch selectedCategory {
        case "Favorite":
            docs = docs.filter { favs.contains($0.id.uuidString) }
        case "Expiring":
            docs = docs.filter(\.isExpiringSoon)
        case let cat? where cat != "All":
            docs = docs.filter { $0.category == cat }
        default:
            break
        }
        if !search.isEmpty {
            // Honest search ladder (D6): full-field keyword incl. OCR text +
            // tags, then synonym-aware RO/EN matching. See DocumentSearch.
            docs = docs.filter { DocumentSearch.matches($0, query: search) }
        }
        switch sortOrder {
        case .recent:
            return docs   // service order: newest first
        case .name:
            return docs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .expiry:
            // Documents with an expiry first, soonest first (ISO strings
            // compare chronologically); undated ones sink to the bottom.
            return docs.sorted {
                switch ($0.expiresAt, $1.expiresAt) {
                case let (a?, b?): return a < b
                case (_?, nil):    return true
                default:           return false
                }
            }
        }
    }

    var body: some View {
        // One pass per render: favorites are read once (they were hitting
        // UserDefaults per row) and the filter runs once instead of per use.
        let _ = favRefresh
        let favs = DocumentFavoritesStore.ids()
        let docs = filtered(favs: favs)
        let expiringCount = documentService.expiringDocs.count
        // The sweep only feeds the top-of-list banner, so skip its work entirely
        // while the user is searching or filtering a category.
        let reviewCount = (selectedCategory == nil && search.isEmpty)
            ? DocumentValidation.sweep(documentService.documents)
                .filter { !DocReviewDismissStore.isDismissed($0.id) }.count
            : 0

        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                categoryChips(favs: favs, expiringCount: expiringCount)
                if documentService.isLoading {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if docs.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            if reviewCount > 0 && selectedCategory == nil && search.isEmpty {
                                reviewBanner(count: reviewCount)
                            }
                            if expiringCount > 0 && selectedCategory == nil && search.isEmpty {
                                expiringBanner
                            }
                            ForEach(docs) { doc in
                                let locked = ItemLockStore.isLocked(doc.id.uuidString, in: .documents)
                                DocumentRow(
                                    doc: doc,
                                    isFavorite: favs.contains(doc.id.uuidString),
                                    isLocked: locked,
                                    onOpen: { selectedDoc = doc },
                                    onPreview: { withLockCheck(doc) { openDocument(doc) } },
                                    onShare: { withLockCheck(doc) { shareDocument(doc) } },
                                    onDelete: { docToDelete = doc; showDeleteConfirm = true },
                                    onFavorite: {
                                        HapticFeedback.selection()
                                        DocumentFavoritesStore.toggle(doc.id)
                                        favRefresh += 1
                                    },
                                    onEdit: { withLockCheck(doc) { editDoc = doc } },
                                    onLock: { toggleLock(doc) }
                                )
                                .padding(.horizontal, AppSpacing.xl)
                            }
                        }
                        .padding(.top, AppSpacing.xxs)
                        .padding(.bottom, 120)
                    }
                    .refreshable { await documentService.load() }
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search documents..."))
        .floatingSpeedDial(.documents)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 5) {
                    sortMenu
                        .frame(width: 38, height: 32)
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 0.5, height: 18)
                    if DocumentScannerView.isSupported {
                        Button {
                            if propertyService.primary == nil {
                                errorToast = "Please set up your property first in Settings."
                            } else {
                                showScanner = true
                            }
                        } label: {
                            Image(systemName: "doc.viewfinder")
                                .font(AppFont.subheadline)
                                .frame(width: 38, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("doc_scan_pdf"))
                        Rectangle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 0.5, height: 18)
                    }
                    Button {
                        if propertyService.primary == nil {
                            errorToast = "Please set up your property first in Settings."
                        } else {
                            showAdd = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(AppFont.subheadline)
                            .frame(width: 38, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add document")
                }
            }
        }
        .task { await documentService.load() }
        .sheet(isPresented: $showAdd, onDismiss: { pendingScan = nil }) {
            if let propertyId = propertyService.primary?.id {
                AddDocumentSheet(propertyId: propertyId, initialScan: pendingScan) {
                    await documentService.load()
                }
                .environment(documentService)
            }
        }
        .fullScreenCover(isPresented: $showScanner, onDismiss: {
            // Present the add sheet only once the scanner cover is fully gone —
            // presenting while dismissing gets silently dropped by UIKit.
            if pendingScan != nil { showAdd = true }
        }) {
            DocumentScannerView { result in
                pendingScan = result   // nil on cancel → nothing opens
                showScanner = false
            }
            .ignoresSafeArea()
        }
        .navigationDestination(item: $selectedDoc) { doc in
            DocumentDetailView(doc: doc).environment(documentService)
        }
        .sheet(item: $editDoc) { doc in
            EditDocumentSheet(doc: doc) { updated in Task { await documentService.update(updated) } }
        }
        .sheet(isPresented: $showReview) {
            DocumentReviewInboxView(onEdit: { doc in editDoc = doc })
                .environment(documentService)
        }
        .confirmationDialog("Delete \"\(docToDelete?.name ?? String(localized: "document"))\"?",
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let doc = docToDelete {
                    Task { await documentService.delete(doc) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the file and cannot be undone.")
        }
        .quickLookPreview($previewURL)
        .sheet(item: $sharePayload) { ShareSheet(activityItems: $0.items) }
        .onChange(of: documentService.error) { _, err in
            if let err { errorToast = err }
        }
        .overlay(alignment: .bottom) {
            if let msg = errorToast {
                toastView(msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 110)
                    .onAppear {
                        Task { try? await Task.sleep(for: .milliseconds(3500)); withAnimation { errorToast = nil } }
                    }
            }
        }
    }

    /// Runs `action` immediately for unlocked documents; locked ones require
    /// Face ID / passcode first.
    private func withLockCheck(_ doc: DocumentModel, _ action: @escaping () -> Void) {
        guard ItemLockStore.isLocked(doc.id.uuidString, in: .documents) else { action(); return }
        Task {
            if await PrivacyAuth.authenticate(reason: String(localized: "Unlock \"\(doc.name)\"")) {
                await MainActor.run { action() }
            }
        }
    }

    /// Locking is free; removing a lock itself requires authentication.
    private func toggleLock(_ doc: DocumentModel) {
        let id = doc.id.uuidString
        if ItemLockStore.isLocked(id, in: .documents) {
            Task {
                if await PrivacyAuth.authenticate(reason: String(localized: "Remove lock from \"\(doc.name)\"")) {
                    await MainActor.run {
                        ItemLockStore.setLocked(id, in: .documents, false)
                        HapticFeedback.success()
                        favRefresh += 1   // lock state is UserDefaults-backed, like favorites
                    }
                }
            }
        } else {
            ItemLockStore.setLocked(id, in: .documents, true)
            HapticFeedback.success()
            favRefresh += 1
        }
    }

    private func openDocument(_ doc: DocumentModel) {
        guard let url = URL(string: doc.fileUrl) else { return }
        if doc.mimeType == "application/pdf" || doc.mimeType?.hasPrefix("image/") == true {
            Task {
                if let data = try? Data(contentsOf: url) {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(doc.fileName)
                    try? data.write(to: tmp)
                    await MainActor.run { previewURL = tmp }
                } else {
                    await UIApplication.shared.open(url)
                }
            }
        } else {
            UIApplication.shared.open(url)
        }
    }

    private func shareDocument(_ doc: DocumentModel) {
        guard let url = URL(string: doc.fileUrl) else { return }
        Task {
            // Item-based presentation: present only once the payload exists, so
            // the first tap is never a blank share sheet (see SharePayload).
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(doc.fileName)
                try? data.write(to: tmp)
                await MainActor.run { sharePayload = SharePayload([tmp]) }
            } else {
                await MainActor.run { sharePayload = SharePayload([url]) }
            }
        }
    }

    private func toastView(_ message: String) -> some View {
        Text(LocalizedStringKey(message))
            .font(AppFont.scaled(13, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .background(.red.opacity(0.85), in: Capsule())
            .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Category chips (filters, always visible — the old toolbar
    // menu hid the categories behind a tap nobody discovered)

    private func categoryChips(favs: Set<String>, expiringCount: Int) -> some View {
        let counts = Dictionary(grouping: documentService.documents, by: \.category)
            .mapValues(\.count)
        let favCount = documentService.documents.filter { favs.contains($0.id.uuidString) }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                GlassFilterChip(label: docCategoryName("All"),
                                systemImage: "square.grid.2x2.fill",
                                count: documentService.documents.count,
                                isSelected: selectedCategory == nil) {
                    HapticFeedback.selection()
                    withAnimation(.snappy(duration: 0.25)) { selectedCategory = nil }
                }
                if expiringCount > 0 {
                    GlassFilterChip(label: String(localized: "doc_filter_expiring"),
                                    systemImage: "exclamationmark.triangle.fill",
                                    count: expiringCount,
                                    isSelected: selectedCategory == "Expiring") {
                        HapticFeedback.selection()
                        withAnimation(.snappy(duration: 0.25)) { selectedCategory = "Expiring" }
                    }
                }
                if favCount > 0 {
                    GlassFilterChip(label: docCategoryName("Favorite"),
                                    systemImage: "star.fill",
                                    count: favCount,
                                    isSelected: selectedCategory == "Favorite") {
                        HapticFeedback.selection()
                        withAnimation(.snappy(duration: 0.25)) { selectedCategory = "Favorite" }
                    }
                }
                // Only categories that actually contain documents.
                ForEach(categories.dropFirst(2), id: \.self) { cat in
                    if let count = counts[cat], count > 0 {
                        GlassFilterChip(label: docCategoryName(cat),
                                        systemImage: categoryIcon(for: cat),
                                        count: count,
                                        isSelected: selectedCategory == cat) {
                            HapticFeedback.selection()
                            withAnimation(.snappy(duration: 0.25)) { selectedCategory = cat }
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    // MARK: - Sort menu

    private var sortMenu: some View {
        Menu {
            Picker("doc_sort_menu", selection: $sortOrder) {
                Label("doc_sort_recent", systemImage: "clock").tag(DocSort.recent)
                Label("doc_sort_name", systemImage: "textformat").tag(DocSort.name)
                Label("doc_sort_expiry", systemImage: "calendar.badge.exclamationmark").tag(DocSort.expiry)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(AppFont.headline)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("doc_sort_menu")
    }

    private func categoryIcon(for cat: String) -> String {
        switch cat {
        case "Favorite":    return "star.fill"
        case "warranty":    return "checkmark.seal.fill"
        case "contract":    return "doc.text.fill"
        case "legal":       return "building.columns.fill"
        case "insurance":   return "shield.fill"
        case "certificate": return "star.seal.fill"
        case "manual":      return "book.fill"
        case "invoice":     return "banknote.fill"
        case "permit":      return "checkmark.shield.fill"
        case "tax":         return "percent"
        case "utility":     return "bolt.fill"
        case "photo":       return "photo.fill"
        default:            return "folder.fill"
        }
    }

    /// Filter chip labels. The two pseudo-filters have their own keys; every
    /// real category goes through the one shared type-name mapping, so the
    /// chips and the type badges can never disagree ("Factură" vs "Invoice").
    private func docCategoryName(_ cat: String) -> String {
        switch cat {
        case "All":      return String(localized: "doc_filter_all")
        case "Favorite": return String(localized: "doc_filter_favorites")
        default:         return DocumentTypeDisplay.name(cat)
        }
    }

    // MARK: - Review inbox banner (D6)

    private func reviewBanner(count: Int) -> some View {
        Button {
            HapticFeedback.selection()
            showReview = true
        } label: {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .foregroundStyle(.blue).font(AppFont.scaled(18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(count == 1 ? "doc_val_banner_one" : "doc_val_banner_many")
                            .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                        Text("doc_val_banner_sub")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                    Text("\(count)")
                        .font(AppFont.captionEmphasis).monospacedDigit()
                        .foregroundStyle(.blue)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.14), in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.xl)
        .accessibilityLabel(Text("doc_val_banner_many"))
    }

    // MARK: - Expiring banner

    private var expiringBanner: some View {
        Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.25)) { selectedCategory = "Expiring" }
        } label: {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(AppFont.scaled(18))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(documentService.expiringDocs.count == 1 ? "1 document expiring soon" : "\(documentService.expiringDocs.count) documents expiring soon")
                            .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                        Text("Review and renew before they expire")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Empty

    private var emptyState: some View {
        Group {
            if search.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No documents yet",
                    message: "Tap + to add your first document"
                )
            } else {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    title: "No results found"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let doc: DocumentModel
    var isFavorite: Bool = false
    var isLocked: Bool = false
    let onOpen: () -> Void
    let onPreview: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    var onFavorite: () -> Void = {}
    var onEdit: () -> Void = {}
    var onLock: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            GlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(Color.primary.opacity(0.08)).frame(width: 48, height: 48)
                        Image(systemName: doc.categoryIcon)
                            .font(AppFont.scaled(18, weight: .medium))
                            .foregroundStyle(categoryColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(doc.name)
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(.primary).lineLimit(1)
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(AppFont.scaled(11)).foregroundStyle(.teal)
                            }
                            if isFavorite {
                                Image(systemName: "star.fill")
                                    .font(AppFont.scaled(11)).foregroundStyle(.yellow)
                            }
                            if doc.isCritical {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(AppFont.scaled(12)).foregroundStyle(.red)
                            }
                        }
                        HStack(spacing: 8) {
                            Text(DocumentTypeDisplay.name(doc.category))
                                .font(AppFont.caption2)
                                .foregroundStyle(categoryColor.opacity(0.8))
                                .padding(.horizontal, AppSpacing.xs).padding(.vertical, 2)
                                .background(categoryColor.opacity(0.12), in: Capsule())
                            if !doc.fileSizeDisplay.isEmpty {
                                Text(doc.fileSizeDisplay)
                                    .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            }
                        }
                        // Expiry, made visible: inside 30 days it becomes a
                        // colored chip (danger within 7 / after expiry);
                        // further out, the plain dated line as before.
                        if let days = doc.daysUntilExpiry {
                            if days <= 30 {
                                DocumentExpiryChip(days: days)
                            } else if let expiry = doc.expiresDisplay {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar").font(AppFont.scaled(10))
                                    Text("Expires \(expiry)").font(AppFont.scaled(11))
                                }
                                .foregroundStyle(Color.primary.opacity(0.4))
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward.square")
                        .font(AppFont.scaled(18)).foregroundStyle(Color.accentColor.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onPreview() } label: { Label("Open file", systemImage: "eye") }
            Button { onShare() } label: { Label("Share", systemImage: "square.and.arrow.up") }
            Button { onFavorite() } label: {
                Label(isFavorite ? "Remove from favorites" : "Add to favorites",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button { onLock() } label: {
                Label(isLocked ? "Remove Face ID lock" : "Lock with Face ID",
                      systemImage: isLocked ? "lock.open" : "lock")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            if isLocked {
                LockedItemPreview(name: doc.name)
            } else {
                DocumentPreviewCard(doc: doc, isFavorite: isFavorite)
            }
        }
        .swipeActions(edge: .leading) {
            Button { onShare() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.accentColor)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var categoryColor: Color {
        switch doc.category {
        case "warranty":    return .yellow
        case "contract":    return .blue
        case "insurance":   return Color.brandSuccess
        case "certificate": return .purple
        case "manual":      return .cyan
        case "invoice":     return .orange
        case "photo":       return .pink
        default:            return .white
        }
    }
}

// MARK: - Long-press preview (PreviewCard)
//
// The document's lifted context-menu card: image documents show their real
// thumbnail, everything else the category glyph; rows carry only fields the
// row actually has (added date always, size and expiry when present).
// Locked documents never reach this view — the row shows LockedItemPreview.
struct DocumentPreviewCard: View {
    let doc: DocumentModel
    var isFavorite: Bool = false

    private var tint: Color { documentCategoryColor(doc.category) }
    private var isImage: Bool { doc.mimeType?.hasPrefix("image/") == true }

    var body: some View {
        PreviewCard(
            title: Text(verbatim: doc.name),
            subtitle: Text(verbatim: DocumentTypeDisplay.name(doc.category)),
            tint: tint,
            details: details,
            chips: chips
        ) {
            thumbnail
        }
    }

    private var details: [PreviewCardDetail] {
        var rows: [PreviewCardDetail] = []
        if let added = ISODate.date(from: doc.createdAt) {
            rows.append(PreviewCardDetail(icon: "calendar",
                                          label: Text("preview_added"),
                                          value: Text(verbatim: AppDate.monthDayYear.string(from: added))))
        }
        if !doc.fileSizeDisplay.isEmpty {
            rows.append(PreviewCardDetail(icon: "externaldrive",
                                          label: Text("preview_size"),
                                          value: Text(verbatim: doc.fileSizeDisplay)))
        }
        if let expiry = doc.expiresDisplay {
            rows.append(PreviewCardDetail(icon: "calendar.badge.exclamationmark",
                                          label: Text("doc_f_expires"),
                                          value: Text(verbatim: expiry)))
        }
        return rows
    }

    private var chips: [PreviewCardChip] {
        var chips: [PreviewCardChip] = []
        if isFavorite {
            chips.append(PreviewCardChip(icon: "star.fill", text: Text("Favorite"), tint: .yellow))
        }
        if doc.isCritical {
            chips.append(PreviewCardChip(icon: "exclamationmark.circle.fill",
                                         text: Text("Critical"), tint: .brandDanger))
        }
        return chips
    }

    /// Real thumbnail for image documents; the category glyph disc otherwise.
    /// While the image loads (or if it fails) the glyph stands in — never a
    /// blank placeholder.
    @ViewBuilder private var thumbnail: some View {
        if isImage {
            StorageImage(source: doc.fileUrl) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    glyphDisc
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        } else {
            glyphDisc.frame(width: 54, height: 54)
        }
    }

    private var glyphDisc: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(tint.opacity(AppOpacity.tintedFill))
            Image(systemName: doc.categoryIcon)
                .font(AppFont.scaled(22, weight: .medium))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Expiry chip
//
// The visible countdown a document with expires_at deserves (the backend has
// notified from it since migration 111 — the UI now shows it too). Rendered on
// the list row and the detail header ONLY when it means something: within 30
// days (warning), within 7 days or already past (danger). No expiry date, or a
// far-away one → no chip.
struct DocumentExpiryChip: View {
    /// Whole calendar days until expiry (negative = expired). See
    /// `DocumentModel.daysUntilExpiry`.
    let days: Int

    private var tint: Color { days <= 7 ? .brandDanger : .brandWarning }

    private var label: String {
        if days < 0 { return String(localized: "doc_exp_chip_expired") }
        if days == 0 { return String(localized: "doc_exp_chip_today") }
        if days == 1 { return String(localized: "doc_exp_chip_tomorrow") }
        return String(format: String(localized: "doc_exp_chip_days"), Int64(days))
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: days < 0 ? "exclamationmark.triangle.fill" : "calendar.badge.exclamationmark")
                .font(AppFont.scaled(10))
            Text(label).font(AppFont.scaled(11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 2)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityLabel(Text(label))
    }
}
