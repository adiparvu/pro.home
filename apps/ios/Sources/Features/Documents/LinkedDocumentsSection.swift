import SwiftUI

// MARK: - Linked documents section (Document Intelligence D4, reverse view)
//
// The "papers attached to me" card for any target object's page — the fridge
// showing its warranty, invoice and manual. It reads the reverse of a
// document's links (document_links keyed by target) and resolves them against
// the already-loaded document set.
//
// Honesty law: if the object has no papers, the section renders NOTHING — no
// empty card ever appears on an unrelated page. It only shows up when there is
// something real to show, and every row is a live document the user can open.

struct LinkedDocumentsSection: View {
    let targetKind: DocumentTargetKind
    let targetId: UUID

    @Environment(DocumentService.self) private var documentService
    @State private var linkedIds: [UUID] = []

    /// Preserves the link order returned by the query while resolving to the
    /// documents actually visible to the user (RLS + property scope).
    private var linkedDocs: [DocumentModel] {
        linkedIds.compactMap { id in documentService.documents.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if !linkedDocs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill").font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(.blue)
                        Text("doc_rel_papers_title").font(AppFont.captionStrong).textCase(.uppercase).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(linkedDocs.count)")
                            .font(AppFont.caption).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    .padding(.leading, AppSpacing.sm)

                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(linkedDocs.enumerated()), id: \.element.id) { idx, doc in
                                if idx > 0 { divider }
                                docRow(doc)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func docRow(_ doc: DocumentModel) -> some View {
        NavigationLink {
            DocumentDetailView(doc: doc).environment(documentService)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: doc.categoryIcon).font(AppFont.scaled(18))
                    .foregroundStyle(documentCategoryColor(doc.category)).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    Text(DocumentTypeDisplay.name(doc.category)).font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                Spacer()
                Image(systemName: "chevron.right").font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 46)
    }

    private func load() async {
        linkedIds = await DocumentLinksService.documentIds(forTarget: targetKind, targetId: targetId)
    }
}
