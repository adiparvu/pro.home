import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct DocumentsView: View {
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var propertyService: PropertyService
    @State private var search = ""
    @State private var selectedCategory: String? = nil
    @State private var showAdd = false
    @State private var docToDelete: DocumentModel?
    @State private var showDeleteConfirm = false
    @State private var previewURL: URL?
    @State private var errorToast: String?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    private let categories = ["All", "warranty", "contract", "insurance",
                               "certificate", "manual", "invoice", "photo", "other"]

    var filteredDocuments: [DocumentModel] {
        var docs = documentService.documents
        if let cat = selectedCategory, cat != "All" {
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
                searchBar
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.md)

                if documentService.isLoading {
                    Spacer()
                    ProgressView().tint(.white)
                    Spacer()
                } else if filteredDocuments.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            if !documentService.expiringDocs.isEmpty && selectedCategory == nil && search.isEmpty {
                                expiringBanner
                            }
                            ForEach(filteredDocuments) { doc in
                                DocumentRow(doc: doc) {
                                    openDocument(doc)
                                } onShare: {
                                    shareDocument(doc)
                                } onDelete: {
                                    docToDelete = doc
                                    showDeleteConfirm = true
                                }
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
        .floatingSpeedDial(.documents)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
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
                    .environmentObject(documentService)
            }
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

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Search documents...", text: $search)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.4))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        case "warranty":    return "checkmark.seal.fill"
        case "contract":    return "doc.text.fill"
        case "insurance":   return "shield.fill"
        case "certificate": return "star.seal.fill"
        case "manual":      return "book.fill"
        case "invoice":     return "banknote.fill"
        case "photo":       return "photo.fill"
        default:            return "folder.fill"
        }
    }

    private func countFor(_ cat: String) -> Int {
        documentService.documents.filter { $0.category == cat }.count
    }

    private func docCategoryName(_ cat: String) -> String {
        switch cat {
        case "warranty":    return "Garanție"
        case "contract":    return "Contract"
        case "insurance":   return "Asigurare"
        case "certificate": return "Certificat"
        case "manual":      return "Manual"
        case "invoice":     return "Factură"
        case "photo":       return "Fotografie"
        default:            return "Altele"
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
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 52)).foregroundStyle(Color.primary.opacity(0.15))
            VStack(spacing: 8) {
                Text(LocalizedStringKey(search.isEmpty ? "No documents yet" : "No results found"))
                    .font(AppFont.title3).foregroundStyle(Color.primary.opacity(0.6))
                if search.isEmpty {
                    Text("Tap + to add your first document")
                        .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let doc: DocumentModel
    let onOpen: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            GlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            Button { onShare() } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
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
        case "insurance":   return Color(red: 0.3, green: 0.85, blue: 0.5)
        case "certificate": return .purple
        case "manual":      return .cyan
        case "invoice":     return .orange
        case "photo":       return .pink
        default:            return .white
        }
    }
}
