import SwiftUI

struct DocumentsView: View {
    @EnvironmentObject private var documentService: DocumentService
    @State private var search = ""
    @State private var selectedCategory: String? = nil

    private let categories = ["All", "warranty", "contract", "insurance", "certificate", "manual", "invoice", "photo"]

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
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                PageHeader(title: "Documents")
                    .padding(.bottom, 12)

                searchBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                categoryFilter
                    .padding(.bottom, 16)

                if documentService.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
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
                                DocumentRow(doc: doc)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 110)
                    }
                    .refreshable { await documentService.load() }
                }
            }
        }
        .task { await documentService.load() }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search documents...", text: $search)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.blue)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Category filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { cat in
                    let isAll = cat == "All"
                    let isSelected = isAll ? selectedCategory == nil : selectedCategory == cat
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            selectedCategory = isAll ? nil : cat
                        }
                    } label: {
                        Text(isAll ? "All" : cat.capitalized)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? .white : .white.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Expiring banner

    private var expiringBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(documentService.expiringDocs.count) document\(documentService.expiringDocs.count == 1 ? "" : "s") expiring soon")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Review and renew before they expire")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.2))
            Text(search.isEmpty ? "No documents yet" : "No results found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let doc: DocumentModel

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                    Image(systemName: doc.categoryIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(categoryColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(doc.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if doc.isCritical {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }
                    HStack(spacing: 8) {
                        Text(doc.category.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(categoryColor.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.12), in: Capsule())

                        if !doc.fileSizeDisplay.isEmpty {
                            Text(doc.fileSizeDisplay)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    if let expiry = doc.expiresDisplay {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text("Expires \(expiry)")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(doc.isExpiringSoon ? .orange : .white.opacity(0.4))
                    }
                }

                Spacer()

                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.25))
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

