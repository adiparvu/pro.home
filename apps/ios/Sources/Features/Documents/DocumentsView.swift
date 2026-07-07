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

    var filteredDocuments: [DocumentModel] {
        _ = favRefresh
        var docs = documentService.documents
        if selectedCategory == "Favorite" {
            let favs = DocumentFavoritesStore.ids()
            docs = docs.filter { favs.contains($0.id.uuidString) }
        } else if let cat = selectedCategory, cat != "All" {
            docs = docs.filter { $0.category == cat }
        }
        if !search.isEmpty {
            docs = docs.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                $0.category.localizedCaseInsensitiveContains(search)
            }
        }
        return docs
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                if documentService.isLoading {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if filteredDocuments.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            if !documentService.expiringDocs.isEmpty && selectedCategory == nil && search.isEmpty {
                                expiringBanner
                            }
                            ForEach(filteredDocuments) { doc in
                                let locked = ItemLockStore.isLocked(doc.id.uuidString, in: .documents)
                                DocumentRow(
                                    doc: doc,
                                    isFavorite: DocumentFavoritesStore.isFavorite(doc.id),
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
                    filterMenu
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
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .background(.red.opacity(0.85), in: Capsule())
            .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Category filter menu

    private var filterMenu: some View {
        Menu {
            Button {
                withAnimation(.spring(response: 0.25)) { selectedCategory = nil }
            } label: {
                Label("All  (\(documentService.documents.count))",
                      systemImage: selectedCategory == nil ? "checkmark" : "square.grid.2x2.fill")
            }
            ForEach(categories.dropFirst(), id: \.self) { cat in
                Button {
                    withAnimation(.spring(response: 0.25)) { selectedCategory = cat }
                } label: {
                    Label("\(docCategoryName(cat))  (\(countFor(cat)))",
                          systemImage: selectedCategory == cat ? "checkmark" : categoryIcon(for: cat))
                }
            }
        } label: {
            Image(systemName: selectedCategory == nil
                  ? "line.3.horizontal.decrease"
                  : selectedCategory.map { categoryIcon(for: $0) } ?? "line.3.horizontal.decrease")
                .font(AppFont.headline)
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Filter documents")
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

    private func countFor(_ cat: String) -> Int {
        if cat == "Favorite" {
            _ = favRefresh
            let favs = DocumentFavoritesStore.ids()
            return documentService.documents.filter { favs.contains($0.id.uuidString) }.count
        }
        return documentService.documents.filter { $0.category == cat }.count
    }

    private func docCategoryName(_ cat: String) -> String {
        let ro = Locale.appIsRomanian
        switch cat {
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
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(documentService.expiringDocs.count == 1 ? "1 document expiring soon" : "\(documentService.expiringDocs.count) documents expiring soon")
                        .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                    Text("Review and renew before they expire")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                Spacer()
            }
        }
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
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(categoryColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(doc.name)
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(.primary).lineLimit(1)
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11)).foregroundStyle(.teal)
                            }
                            if isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11)).foregroundStyle(.yellow)
                            }
                            if doc.isCritical {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12)).foregroundStyle(.red)
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
                                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            }
                        }
                        if let expiry = doc.expiresDisplay {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar").font(.system(size: 10))
                                Text("Expires \(expiry)").font(.system(size: 11))
                            }
                            .foregroundStyle(doc.isExpiringSoon ? .orange : Color.primary.opacity(0.4))
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 18)).foregroundStyle(Color.accentColor.opacity(0.7))
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
