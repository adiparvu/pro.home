import SwiftUI

// MARK: - Validation review inbox (Document Intelligence D6)
//
// The one place the three validation sweeps surface, each finding paired with a
// one-tap fix:
//   • incomplete → "Complete"  hands the document back to the editor (onEdit).
//   • expired    → "Renew"     hands the document back to the editor (onEdit).
//   • duplicate  → per-document Delete, so the extra copy goes in one tap.
// A finding can also be dismissed ("I've reviewed this"), stored per-device.

struct DocumentReviewInboxView: View {
    /// Hands a document back to the parent to present its editor (the inbox is
    /// itself a sheet, so it can't stack another one cleanly).
    var onEdit: (DocumentModel) -> Void

    @Environment(DocumentService.self) private var documentService
    @Environment(\.dismiss) private var dismiss

    @State private var refresh = 0
    @State private var pendingDelete: DocumentModel?

    private var issues: [DocValidationIssue] {
        let _ = refresh
        return DocumentValidation.sweep(documentService.documents)
            .filter { !DocReviewDismissStore.isDismissed($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                if issues.isEmpty {
                    EmptyStateView(icon: "checkmark.seal.fill",
                                   title: "doc_val_all_clear_title",
                                   message: "doc_val_all_clear_msg")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(issues) { issue in
                                issueCard(issue)
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.lg)
                    }
                }
            }
            .navigationTitle("doc_val_inbox_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.accentColor)
                }
            }
            .confirmationDialog("doc_val_delete_dup_q",
                                isPresented: .init(get: { pendingDelete != nil },
                                                   set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let d = pendingDelete {
                        Task { await documentService.delete(d); await MainActor.run { refresh += 1 } }
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            }
        }
    }

    // MARK: Issue card

    @ViewBuilder
    private func issueCard(_ issue: DocValidationIssue) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: 10) {
                    Image(systemName: issue.kind.icon)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(issue.kind.tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.kind.titleKey)
                            .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                        subtitle(for: issue)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                    Button {
                        HapticFeedback.selection()
                        DocReviewDismissStore.dismiss(issue.id)
                        withAnimation(.snappy) { refresh += 1 }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFont.scaled(16)).foregroundStyle(Color.primary.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("doc_val_dismiss")
                }

                switch issue.kind {
                case .duplicate:
                    duplicateBody(issue)
                case .expired:
                    fixRow(issue.primary, action: "doc_val_fix_renew", icon: "arrow.triangle.2.circlepath")
                case .incomplete:
                    missingChips(issue.missing)
                    fixRow(issue.primary, action: "doc_val_fix_complete", icon: "pencil")
                }
            }
        }
    }

    @ViewBuilder
    private func subtitle(for issue: DocValidationIssue) -> some View {
        switch issue.kind {
        case .duplicate:
            Text(verbatim: "\(issue.cluster.count)× · \(issue.sharedKey ?? "—")")
        case .expired:
            if let e = issue.primary.expiresDisplay {
                Text(verbatim: "\(issue.primary.name) · \(e)")
            } else {
                Text(issue.primary.name)
            }
        case .incomplete:
            Text(issue.primary.name)
        }
    }

    /// The still-empty required fields, as tappable-looking chips (labels only).
    private func missingChips(_ fields: [DocField]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(fields, id: \.self) { field in
                    Text(field.labelKey)
                        .font(AppFont.scaled(11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }
        }
    }

    // MARK: Bodies

    /// The "open this document and fix it" row for expired / incomplete.
    private func fixRow(_ doc: DocumentModel, action: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: doc.categoryIcon)
                .font(AppFont.scaled(14)).foregroundStyle(documentCategoryColor(doc.category))
                .frame(width: 22)
            Text(doc.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            Button {
                HapticFeedback.selection()
                dismiss()
                onEdit(doc)
            } label: {
                Label(action, systemImage: icon)
                    .font(AppFont.captionEmphasis).foregroundStyle(Color.accentColor)
                    .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// The duplicate cluster: every copy listed, each deletable in one tap.
    private func duplicateBody(_ issue: DocValidationIssue) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(issue.cluster.enumerated()), id: \.element.id) { idx, doc in
                if idx > 0 {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
                }
                HStack(spacing: 10) {
                    Image(systemName: doc.categoryIcon)
                        .font(AppFont.scaled(14)).foregroundStyle(documentCategoryColor(doc.category))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(doc.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                        Text(dateLabel(doc)).font(AppFont.scaled(11))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    Spacer()
                    Button(role: .destructive) {
                        HapticFeedback.warning()
                        pendingDelete = doc
                    } label: {
                        Image(systemName: "trash")
                            .font(AppFont.scaled(13)).foregroundStyle(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("doc_val_delete_dup")
                }
                .padding(.vertical, AppSpacing.sm)
            }
        }
    }

    private func dateLabel(_ doc: DocumentModel) -> String {
        String(doc.createdAt.prefix(10))
    }
}
