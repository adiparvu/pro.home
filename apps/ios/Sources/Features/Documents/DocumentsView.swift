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
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var selectedDoc: DocumentModel?
    @State private var editDoc: DocumentModel?
    // Bumped when a favorite toggles so the (UserDefaults-backed) filter/badges refresh.
    @State private var favRefresh = 0

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
            docs = docs.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.category.localizedCaseInsensitiveContains(search)
            }
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
                            if expiringCount > 0 && selectedCategory == nil && search.isEmpty {
                                expiringBanner
                            }
                            ForEach(docs) { doc in
                                let locked = ItemLockStore.isLocked(doc.id.uuidString, in: .documents)
                                DocumentRow(
                                    doc: doc,
                                    isFavorite: favs.contains(doc.id.uuidString),
                                    isLocked: locked,
                                    onOpen: { withLockCheck(doc) { selectedDoc = doc } },
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
        .sheet(isPresented: $showAdd) {
            if let propertyId = propertyService.primary?.id {
                AddDocumentSheet(propertyId: propertyId) { await documentService.load() }
                    .environment(documentService)
            }
        }
        .navigationDestination(item: $selectedDoc) { doc in
            DocumentDetailView(doc: doc).environment(documentService)
        }
        .sheet(item: $editDoc) { doc in
            EditDocumentSheet(doc: doc) { updated in Task { await documentService.update(updated) } }
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
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
            if let data = try? Data(contentsOf: url) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(doc.fileName)
                try? data.write(to: tmp)
                await MainActor.run {
                    shareItems = [tmp]
                    showShareSheet = true
                }
            } else {
                await MainActor.run {
                    shareItems = [url]
                    showShareSheet = true
                }
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
                chip(nil, label: docCategoryName("All"), icon: "square.grid.2x2.fill",
                     count: documentService.documents.count)
                if expiringCount > 0 {
                    chip("Expiring", label: String(localized: "doc_filter_expiring"),
                         icon: "exclamationmark.triangle.fill", count: expiringCount)
                }
                if favCount > 0 {
                    chip("Favorite", label: docCategoryName("Favorite"),
                         icon: "star.fill", count: favCount)
                }
                // Only categories that actually contain documents.
                ForEach(categories.dropFirst(2), id: \.self) { cat in
                    if let count = counts[cat], count > 0 {
                        chip(cat, label: docCategoryName(cat),
                             icon: categoryIcon(for: cat), count: count)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private func chip(_ value: String?, label: String, icon: String, count: Int) -> some View {
        let isOn = selectedCategory == value
        return Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.25)) { selectedCategory = value }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(AppFont.caption)
                Text(label)
                    .font(AppFont.captionEmphasis)
                Text("\(count)")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(isOn ? 0.6 : 0.35))
                    .monospacedDigit()
            }
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 7)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color.subtleFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
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

    private func docCategoryName(_ cat: String) -> String {
        let ro = Locale.appIsRomanian
        switch cat {
        case "All":         return ro ? "Toate" : "All"
        case "Favorite":    return ro ? "Favorite" : "Favorites"
        case "warranty":    return ro ? "Garanție" : "Warranty"
        case "contract":    return ro ? "Contract" : "Contract"
        case "legal":       return ro ? "Juridic" : "Legal"
        case "insurance":   return ro ? "Asigurare" : "Insurance"
        case "certificate": return ro ? "Certificat" : "Certificate"
        case "manual":      return ro ? "Manual" : "Manual"
        case "invoice":     return ro ? "Factură" : "Invoice"
        case "permit":      return ro ? "Autorizație" : "Permit"
        case "tax":         return ro ? "Taxe" : "Tax"
        case "utility":     return ro ? "Utilități" : "Utility"
        case "photo":       return ro ? "Fotografie" : "Photo"
        default:            return ro ? "Altele" : "Other"
        }
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
                            Text(LocalizedStringKey(doc.category.capitalized))
                                .font(AppFont.caption2)
                                .foregroundStyle(categoryColor.opacity(0.8))
                                .padding(.horizontal, AppSpacing.xs).padding(.vertical, 2)
                                .background(categoryColor.opacity(0.12), in: Capsule())
                            if !doc.fileSizeDisplay.isEmpty {
                                Text(doc.fileSizeDisplay)
                                    .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            }
                        }
                        if let expiry = doc.expiresDisplay {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar").font(AppFont.scaled(10))
                                Text("Expires \(expiry)").font(AppFont.scaled(11))
                            }
                            .foregroundStyle(doc.isExpiringSoon ? .orange : Color.primary.opacity(0.4))
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
                DocumentRowPreview(doc: doc)
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
