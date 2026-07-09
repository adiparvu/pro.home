import SwiftUI
import Supabase

// MARK: - Document relations section (Document Intelligence D4)
//
// A document's two relation sets, rendered on its detail page:
//   • "Linked to"        — the house objects this paper is attached to
//                          (document_links: property / room / appliance / …).
//   • "Related documents" — the papers it chains to (related_documents:
//                          contract → invoice → receipt), in either direction.
//
// Mirrors DocumentFilesSection 1:1 — a header with a "+" capsule, a GlassCard
// list with hairline dividers, swipe / context-menu delete, a confirmation
// dialog, and a lazy `.task` load. Target names are resolved lazily and cached;
// until a name arrives the row shows the kind's own label, never a raw id.

struct DocumentRelationsSection: View {
    let documentId: UUID
    /// When the parent document is read-only (D6), linking / unlinking and
    /// adding / removing related documents are genuinely disabled.
    var readOnly: Bool = false

    @State private var service = DocumentLinksService()
    @Environment(DocumentService.self) private var documentService

    /// Resolved object names, keyed by target id (best-effort, filled lazily).
    @State private var targetNames: [UUID: String] = [:]

    // Link-to-object flow
    @State private var pickingKind: DocumentTargetKind?
    @State private var pendingLinkDelete: DocumentLink?

    // Related-document flow
    @State private var showAddRelated = false
    @State private var pendingRelatedDelete: RelatedDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            linkedGroup
            relatedGroup
        }
        .task { await load() }
        .sheet(item: $pickingKind) { kind in
            DocumentLinkTargetPicker(kind: kind) { id, name in
                pickingKind = nil
                Task { await addLink(kind: kind, targetId: id, name: name) }
            }
        }
        .sheet(isPresented: $showAddRelated) {
            RelatedDocumentPicker(candidates: relatedCandidates) { picked, relation in
                showAddRelated = false
                Task {
                    let ok = await service.addRelated(parentId: documentId, childId: picked.id, relation: relation)
                    ok ? HapticFeedback.success() : HapticFeedback.error()
                }
            }
        }
        .confirmationDialog("doc_rel_unlink_q", isPresented: .init(
            get: { pendingLinkDelete != nil }, set: { if !$0 { pendingLinkDelete = nil } }),
            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let l = pendingLinkDelete { Task { await service.removeLink(l) } }
                pendingLinkDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingLinkDelete = nil }
        }
        .confirmationDialog("doc_rel_remove_q", isPresented: .init(
            get: { pendingRelatedDelete != nil }, set: { if !$0 { pendingRelatedDelete = nil } }),
            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let e = pendingRelatedDelete { Task { await service.removeRelated(e) } }
                pendingRelatedDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingRelatedDelete = nil }
        }
    }

    // MARK: Linked-to-object group

    private var linkedGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link").font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(.blue)
                Text("doc_rel_linked_title").font(AppFont.captionStrong).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                if !service.links.isEmpty {
                    Text("\(service.links.count)")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                if !readOnly { linkMenu }
            }
            .padding(.leading, AppSpacing.sm)

            GlassCard {
                if service.isLoading && service.links.isEmpty {
                    loadingRow
                } else if service.links.isEmpty {
                    emptyState("link.badge.plus", "doc_rel_none_linked")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.links.enumerated()), id: \.element.id) { idx, link in
                            if idx > 0 { divider }
                            linkRow(link)
                        }
                    }
                }
            }
        }
    }

    private var linkMenu: some View {
        Menu {
            Section("doc_rel_pick_kind") {
                ForEach(DocumentTargetKind.allCases) { kind in
                    Button { pickingKind = kind } label: { Label(kind.labelKey, systemImage: kind.icon) }
                }
            }
        } label: {
            addCapsule("doc_rel_add_link")
        }
    }

    private func linkRow(_ link: DocumentLink) -> some View {
        let resolved = targetNames[link.targetId].flatMap { $0.isEmpty ? nil : $0 }
        return HStack(spacing: 12) {
            Image(systemName: link.kind?.icon ?? "link")
                .font(AppFont.scaled(18)).foregroundStyle(.blue).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                if let resolved {
                    Text(resolved).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    if let kind = link.kind {
                        Text(kind.labelKey).font(AppFont.scaled(11))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                } else if let kind = link.kind {
                    Text(kind.labelKey).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                } else {
                    Text(verbatim: "—").font(AppFont.scaled(14)).foregroundStyle(.primary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            if !readOnly {
                Button(role: .destructive) { pendingLinkDelete = link } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .contextMenu {
            if !readOnly {
                Button(role: .destructive) { pendingLinkDelete = link } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    // MARK: Related-document group

    private var relatedGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc.fill").font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(.blue)
                Text("doc_rel_related_title").font(AppFont.captionStrong).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                if !relatedRows.isEmpty {
                    Text("\(relatedRows.count)")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                if !readOnly {
                    Button { showAddRelated = true } label: { addCapsule("doc_rel_add_related") }
                        .buttonStyle(.plain)
                }
            }
            .padding(.leading, AppSpacing.sm)

            GlassCard {
                if relatedRows.isEmpty {
                    emptyState("doc.on.doc", "doc_rel_none_related")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(relatedRows.enumerated()), id: \.element.id) { idx, row in
                            if idx > 0 { divider }
                            relatedRow(row)
                        }
                    }
                }
            }
        }
    }

    private func relatedRow(_ row: RelatedRow) -> some View {
        NavigationLink {
            DocumentDetailView(doc: row.other).environment(documentService)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: row.other.categoryIcon).font(AppFont.scaled(18))
                    .foregroundStyle(documentCategoryColor(row.other.category)).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.other.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: row.isChild ? "arrow.turn.down.right" : "arrow.turn.up.left")
                            .font(AppFont.scaled(9))
                        relationLabel(for: row)
                    }
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if !readOnly {
                Button(role: .destructive) { pendingRelatedDelete = row.edge } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .contextMenu {
            if !readOnly {
                Button(role: .destructive) { pendingRelatedDelete = row.edge } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder
    private func relationLabel(for row: RelatedRow) -> some View {
        if let rel = row.edge.relation, !rel.isEmpty {
            Text(rel)
        } else if row.isChild {
            Text("doc_rel_dir_child")
        } else {
            Text("doc_rel_dir_parent")
        }
    }

    // MARK: Shared bits (identical to DocumentFilesSection)

    private func addCapsule(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
            Text(key).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glassCapsule()
    }

    private func emptyState(_ icon: String, _ text: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(AppFont.scaled(22)).foregroundStyle(Color.primary.opacity(0.25))
            Text(text).font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.lg)
    }

    private var loadingRow: some View {
        HStack { Spacer(); ProgressView().padding(.vertical, AppSpacing.lg); Spacer() }
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 46)
    }

    // MARK: Data

    /// A related edge paired with the resolved other document and its direction.
    private struct RelatedRow: Identifiable {
        let edge: RelatedDocument
        let other: DocumentModel
        /// true → `other` is a child of this document; false → `other` is its parent.
        let isChild: Bool
        var id: UUID { edge.id }
    }

    /// childEdges (this doc → child) and parentEdges (parent → this doc) merged
    /// and resolved to the loaded document set; unresolvable ids are dropped so
    /// a row never points at a paper we can't open (honesty law).
    private var relatedRows: [RelatedRow] {
        var rows: [RelatedRow] = []
        for e in service.childEdges {
            if let other = documentService.documents.first(where: { $0.id == e.childId }) {
                rows.append(RelatedRow(edge: e, other: other, isChild: true))
            }
        }
        for e in service.parentEdges {
            if let other = documentService.documents.first(where: { $0.id == e.parentId }) {
                rows.append(RelatedRow(edge: e, other: other, isChild: false))
            }
        }
        return rows
    }

    /// The property's other documents, minus this one and any already related.
    private var relatedCandidates: [DocumentModel] {
        let taken = Set(service.childEdges.map(\.childId) + service.parentEdges.map(\.parentId))
        return documentService.documents.filter { $0.id != documentId && !taken.contains($0.id) }
    }

    private func load() async {
        await service.load(documentId: documentId)
        await resolveNames()
    }

    private func resolveNames() async {
        for link in service.links where targetNames[link.targetId] == nil {
            guard let kind = link.kind else { continue }
            if let name = await DocumentLinksService.targetName(kind: kind, targetId: link.targetId) {
                targetNames[link.targetId] = name
            }
        }
    }

    private func addLink(kind: DocumentTargetKind, targetId: UUID, name: String) async {
        let ok = await service.addLink(documentId: documentId, kind: kind, targetId: targetId)
        if ok {
            targetNames[targetId] = name
            HapticFeedback.success()
        } else {
            HapticFeedback.error()
        }
    }
}

// MARK: - Object picker (choose which room / appliance / … to link)
//
// Loads {id, name} rows for the chosen kind's table, scoped to the active
// property (every target table carries a `property_id`, except `.property`
// itself which is fetched by its own id). RLS still applies. Rows with no
// usable name are skipped rather than shown as a blank line.

struct DocumentLinkTargetPicker: View {
    let kind: DocumentTargetKind
    var onPick: (UUID, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var isLoading = true
    @State private var search = ""

    struct Row: Identifiable, Decodable {
        let id: UUID
        let name: String?
    }

    private var filtered: [Row] {
        let named = rows.filter { ($0.name?.isEmpty == false) }
        guard !search.isEmpty else { return named }
        return named.filter { ($0.name ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                if isLoading {
                    ProgressView()
                } else if filtered.isEmpty {
                    EmptyStateView(icon: kind.icon, title: "doc_rel_pick_empty", message: nil)
                } else {
                    List {
                        ForEach(filtered) { row in
                            Button {
                                HapticFeedback.selection()
                                onPick(row.id, row.name ?? "")
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: kind.icon).font(AppFont.scaled(16))
                                        .foregroundStyle(.blue).frame(width: 28)
                                    Text(row.name ?? "").font(AppFont.scaled(15)).foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(Text(kind.labelKey))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        guard let pid = PropertyService.activePropertyId else { rows = []; return }
        if kind == .property {
            rows = (try? await supabase.from("properties")
                .select("id,name").eq("id", value: pid.uuidString)
                .execute().value) ?? []
        } else {
            rows = (try? await supabase.from(kind.table)
                .select("id,name").eq("property_id", value: pid.uuidString)
                .order("name", ascending: true)
                .execute().value) ?? []
        }
    }
}

// MARK: - Related-document picker (chain this paper to another)
//
// Lists the property's other documents (already filtered by the caller to
// exclude self + existing links) and offers an optional free-text relation
// ("annex", "renews", …). Picking a document creates the parent→child edge.

struct RelatedDocumentPicker: View {
    let candidates: [DocumentModel]
    var onPick: (DocumentModel, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var relation = ""
    @State private var search = ""

    private var filtered: [DocumentModel] {
        guard !search.isEmpty else { return candidates }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    relationField
                    if candidates.isEmpty {
                        EmptyStateView(icon: "doc.on.doc", title: "doc_rel_related_empty", message: nil)
                    } else {
                        List {
                            ForEach(filtered) { doc in
                                Button {
                                    HapticFeedback.selection()
                                    let rel = relation.trimmingCharacters(in: .whitespacesAndNewlines)
                                    onPick(doc, rel.isEmpty ? nil : rel)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: doc.categoryIcon).font(AppFont.scaled(16))
                                            .foregroundStyle(documentCategoryColor(doc.category)).frame(width: 28)
                                        Text(doc.name).font(AppFont.scaled(15)).foregroundStyle(.primary).lineLimit(1)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("doc_rel_add_related")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var relationField: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.append").font(AppFont.scaled(14)).foregroundStyle(.blue).frame(width: 22)
            TextField("doc_rel_relation_ph", text: $relation)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
        .background(Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.md).padding(.bottom, AppSpacing.sm)
    }
}
