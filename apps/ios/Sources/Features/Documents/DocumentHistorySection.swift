import SwiftUI

// MARK: - Document history section (Document Intelligence D5)
//
// The activity timeline on the document page: created, edited, files added or
// removed, and opens for viewing — newest first. Self-contained like
// DocumentFilesSection / DocumentRelationsSection: it owns its service and
// loads lazily on appear. Events are read-only here; they're written at the
// honest moment each action happens (see DocumentEventsService).
//
// Display refinements (all render-time, storage untouched):
//   • Edited entries list the real per-field diff ("Companie: — → OMV") when
//     the event carries one; older entries without a diff render as before.
//   • Consecutive entries by the same author, same kind, within an hour of
//     each other collapse into one row (with the merged diff and a ×N count),
//     so five quick saves don't read as five identical lines.
//   • Timestamps show the exact time — "yesterday, 21:45", not just
//     "yesterday".

struct DocumentHistorySection: View {
    let documentId: UUID

    @State private var service = DocumentEventsService()

    /// One rendered timeline row — possibly the merge of several raw events.
    private struct DisplayEvent: Identifiable {
        let id: UUID                 // newest merged event's id (stable per group)
        let kind: DocumentEvent.Kind
        let actorId: UUID?
        let date: Date?              // newest instant in the group
        let changes: [DocumentFieldChange]
        let mergedCount: Int
    }

    /// Groups consecutive same-kind, same-author events whose instants are at
    /// most an hour apart, then merges each group into one display row. For
    /// merged edits the diff chains honestly: a field's `old` comes from the
    /// group's oldest event, its `new` from the newest, and fields that ended
    /// up back where they started drop out.
    private var displayEvents: [DisplayEvent] {
        var groups: [[DocumentEvent]] = []
        for event in service.events {                 // newest first
            if let previous = groups.last?.last,
               event.kindEnum == previous.kindEnum,
               event.actorId == previous.actorId,
               let a = previous.date, let b = event.date,
               a.timeIntervalSince(b) <= 3600 {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }
        return groups.compactMap { group in
            guard let newest = group.first else { return nil }
            var newValues: [String: String] = [:]
            var oldValues: [String: String] = [:]
            for event in group {                      // newest → oldest
                for change in event.fieldChanges {
                    if newValues[change.field] == nil { newValues[change.field] = change.new }
                    oldValues[change.field] = change.old   // ends at the oldest
                }
            }
            let ordered = DocumentFieldChange.canonicalOrder + newValues.keys
                .filter { !DocumentFieldChange.canonicalOrder.contains($0) }.sorted()
            let changes = ordered.compactMap { field -> DocumentFieldChange? in
                guard let n = newValues[field], let o = oldValues[field], o != n else { return nil }
                return DocumentFieldChange(field: field, old: o, new: n)
            }
            return DisplayEvent(id: newest.id, kind: newest.kindEnum,
                                actorId: newest.actorId, date: newest.date,
                                changes: changes, mergedCount: group.count)
        }
    }

    var body: some View {
        let rows = displayEvents
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(.blue)
                Text("doc_hist_title").font(AppFont.captionStrong).foregroundStyle(.secondary)
                Spacer()
                if !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
            }
            .padding(.leading, AppSpacing.sm)

            GlassCard {
                if service.isLoading && rows.isEmpty {
                    HStack { Spacer(); ProgressView().padding(.vertical, AppSpacing.lg); Spacer() }
                } else if rows.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, event in
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

    private func eventRow(_ event: DisplayEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.icon).font(AppFont.scaled(16)).foregroundStyle(.blue).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(LocalizedStringKey(event.kind.labelKey))
                        .font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    if event.mergedCount > 1 {
                        // Several quick saves collapsed into this one row.
                        Text(verbatim: "×\(event.mergedCount)")
                            .font(AppFont.scaled(11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                }
                // Who did it — resolved live from the profiles directory so the
                // row always shows the account's current display name.
                if let actorId = event.actorId,
                   let name = MemberDirectory.shared.byId[actorId]?.name, !name.isEmpty {
                    Text(name)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                }
                // What actually changed — only edits that recorded a diff.
                if !event.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(event.changes) { change in
                            Text(verbatim: "\(change.label): \(change.oldDisplay) → \(change.newDisplay)")
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                .lineLimit(2)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
            if let date = event.date {
                Text(Self.timestampDisplay(date))
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

    // MARK: Timestamps — relative day, exact time

    private static let relativeDay: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        return f
    }()

    /// "today, 14:30" / "yesterday, 21:45" / "Jul 6, 14:30" — the named day
    /// keeps the timeline scannable, the exact time makes it auditable.
    private static func timestampDisplay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            let day = relativeDay.localizedString(from: DateComponents(day: cal.isDateInToday(date) ? 0 : -1))
            return "\(day), \(ISODate.timeOnly.string(from: date))"
        }
        return AppDate.monthDayTime.string(from: date)
    }
}
