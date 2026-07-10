import SwiftUI

// MARK: - Document history section (Document Intelligence D5)
//
// The activity timeline on the document page: created, edited, files added or
// removed, and opens for viewing — newest first. Self-contained like
// DocumentFilesSection / DocumentRelationsSection: it owns its service and
// loads lazily on appear. Events are read-only here; they're written at the
// honest moment each action happens (see DocumentEventsService).

struct DocumentHistorySection: View {
    let documentId: UUID

    @State private var service = DocumentEventsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(.blue)
                Text("doc_hist_title").font(AppFont.captionStrong).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                if !service.events.isEmpty {
                    Text("\(service.events.count)")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
            }
            .padding(.leading, AppSpacing.sm)

            GlassCard {
                if service.isLoading && service.events.isEmpty {
                    HStack { Spacer(); ProgressView().padding(.vertical, AppSpacing.lg); Spacer() }
                } else if service.events.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.events.enumerated()), id: \.element.id) { idx, event in
                            if idx > 0 { divider }
                            eventRow(event)
                        }
                    }
                }
            }
        }
        .task {
            // The actor names render from the profiles directory — make sure it
            // is hydrated before the rows appear.
            await MemberDirectory.shared.loadIfNeeded()
            await service.load(documentId: documentId)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock").font(AppFont.scaled(22)).foregroundStyle(Color.primary.opacity(0.25))
            Text("doc_hist_empty").font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.lg)
    }

    private func eventRow(_ event: DocumentEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.icon).font(AppFont.scaled(16)).foregroundStyle(.blue).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(event.labelKey)).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                // Who did it — resolved live from the profiles directory so the
                // row always shows the account's current display name.
                if let actorId = event.actorId,
                   let name = MemberDirectory.shared.byId[actorId]?.name, !name.isEmpty {
                    Text(name)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                }
            }
            Spacer()
            if let date = event.date {
                Text(date, format: .relative(presentation: .named))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 42)
    }
}
