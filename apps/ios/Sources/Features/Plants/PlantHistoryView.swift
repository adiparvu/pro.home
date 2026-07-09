import SwiftUI

// MARK: - Plant history (Plant OS P5)
//
// The plant page's History surface: a quick-action row for logging real care
// actions, and a timeline that merges those events with the plant's photo album
// (migration 122), grouped by month, newest-first.
//
// Honesty rule: a quick action writes an event ONLY for something the user
// actually did. "Am udat / Watered" additionally routes through
// PlantService.markWatered so the plant's last_watered_at / watering state stays
// the single source of truth — the timeline entry is a record of that same act,
// never a second, divergent one.

struct PlantHistorySection: View {
    let plant: Plant
    let plantService: PlantService
    var eventService: PlantEventService
    var photoService: PlantPhotoService

    /// The kinds offered as one-tap quick actions (in row order). `treated`
    /// remains a valid logged kind but isn't a primary quick action.
    private let quickKinds: [PlantEventKind] = [
        .watered, .fertilized, .repotted, .sprayed, .pruned, .note,
    ]

    @State private var showNotePrompt = false
    @State private var noteDraft = ""
    @State private var isLogging = false

    var body: some View {
        VStack(spacing: 12) {
            quickActionsCard
            timeline
        }
        .alert("plant_hist_note_title", isPresented: $showNotePrompt) {
            TextField("plant_hist_note_placeholder", text: $noteDraft)
            Button("Cancel", role: .cancel) { noteDraft = "" }
            Button("plant_hist_note_save") { logNote() }
        } message: {
            Text("plant_hist_note_message")
        }
    }

    // MARK: Quick actions

    private var quickActionsCard: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("plant_hist_title", systemImage: "clock.arrow.circlepath")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    Spacer()
                    if isLogging { ProgressView().scaleEffect(0.7) }
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                    spacing: 12
                ) {
                    ForEach(quickKinds) { kind in
                        quickButton(kind)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quickButton(_ kind: PlantEventKind) -> some View {
        Button {
            if kind == .note {
                HapticFeedback.selection()
                showNotePrompt = true
            } else {
                log(kind)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(kind.tint)
                    .frame(width: 40, height: 40)
                    .glassCircle()
                Text(kind.labelKey)
                    .font(AppFont.scaled(11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(AppOpacity.subtleFill),
                       in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLogging)
    }

    // MARK: Timeline

    @ViewBuilder
    private var timeline: some View {
        let groups = groupedTimeline
        if groups.isEmpty {
            GlassCard(padding: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(AppFont.scaled(26)).foregroundStyle(.secondary)
                    Text("plant_hist_empty")
                        .font(AppFont.scaled(14)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        } else {
            ForEach(groups) { group in
                GlassCard(padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(AppFont.captionStrong).foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { rowDivider }
                            row(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: PlantTimelineItem) -> some View {
        switch item {
        case .event(let event):
            // Manually-logged events are deletable (swipe). Photo rows are not —
            // they're owned by the album (delete happens there).
            SwipeToDeleteRow {
                Task { await eventService.delete(event) }
            } content: {
                eventRow(event)
            }
        case .photo(let photo):
            photoRow(photo)
        }
    }

    private func eventRow(_ event: PlantEvent) -> some View {
        let kind = event.kindEnum
        return HStack(spacing: 12) {
            iconTile(system: kind.icon, tint: kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.labelKey)
                    .font(AppFont.scaled(15, weight: .medium)).foregroundStyle(.primary)
                if let note = event.noteText {
                    Text(note)
                        .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            Text(shortDate(event.date))
                .font(AppFont.scaled(12)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func photoRow(_ photo: PlantPhoto) -> some View {
        HStack(spacing: 12) {
            PlantTimelineThumb(photo: photo)
            VStack(alignment: .leading, spacing: 2) {
                Text("plant_hist_photo")
                    .font(AppFont.scaled(15, weight: .medium)).foregroundStyle(.primary)
                if let note = photo.note, !note.isEmpty {
                    Text(note)
                        .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            Text(shortDate(AppDate.timestamp(from: photo.takenAt)))
                .font(AppFont.scaled(12)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func iconTile(system: String, tint: Color) -> some View {
        Image(systemName: system)
            .font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .glassCircle()
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
    }

    // MARK: Actions

    private func log(_ kind: PlantEventKind, details: [String: String]? = nil) {
        guard !isLogging else { return }
        isLogging = true
        Task {
            // "Watered" keeps the existing watering state authoritative: it runs
            // markWatered (updates last_watered_at + drives the watering Live
            // Activity) and then records the matching timeline event.
            if kind == .watered {
                await plantService.markWatered(plant)
            }
            let row = await eventService.log(
                plantId: plant.id, propertyId: plant.propertyId,
                kind: kind, details: details)
            isLogging = false
            if row != nil { HapticFeedback.success() } else { HapticFeedback.error() }
        }
    }

    private func logNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        noteDraft = ""
        guard !trimmed.isEmpty else { return }
        log(.note, details: ["note": trimmed])
    }

    // MARK: Merge + group

    /// Merges events + photos, newest-first, bucketed by calendar month. The
    /// bucket key uses the stable `yyyy-MM` wire formatter; the section title
    /// uses a locale-aware full-month formatter ("iulie 2026" / "July 2026").
    private var groupedTimeline: [PlantTimelineGroup] {
        var items: [PlantTimelineItem] = eventService.events.map(PlantTimelineItem.event)
        items += photoService.photos.map(PlantTimelineItem.photo)
        items.sort { $0.date > $1.date }

        var order: [String] = []
        var buckets: [String: [PlantTimelineItem]] = [:]
        for item in items {
            let key = AppDate.monthKey.string(from: item.date)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.map { key in
            let rows = buckets[key] ?? []
            let title = rows.first.map { AppDate.monthYear.string(from: $0.date) } ?? key
            return PlantTimelineGroup(id: key, title: title, items: rows)
        }
    }

    private func shortDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "plant_hist_today") }
        if cal.isDateInYesterday(date) { return String(localized: "plant_hist_yesterday") }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return AppDate.monthDay.string(from: date)
        }
        return AppDate.monthDayYear.string(from: date)
    }
}

// MARK: - Timeline item

private enum PlantTimelineItem: Identifiable {
    case event(PlantEvent)
    case photo(PlantPhoto)

    var id: String {
        switch self {
        case .event(let e): return "e-\(e.id.uuidString)"
        case .photo(let p): return "p-\(p.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .event(let e): return e.date ?? .distantPast
        case .photo(let p): return AppDate.timestamp(from: p.takenAt) ?? .distantPast
        }
    }
}

private struct PlantTimelineGroup: Identifiable {
    let id: String
    let title: String
    let items: [PlantTimelineItem]
}

// MARK: - Timeline photo thumbnail (signed-URL resolved)

private struct PlantTimelineThumb: View {
    let photo: PlantPhoto
    @State private var url: URL?

    var body: some View {
        StorageImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFill()
            default:
                Rectangle().fill(Color.primary.opacity(0.06))
                    .overlay(Image(systemName: "photo").font(AppFont.scaled(12)).foregroundStyle(.secondary))
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .task(id: photo.url) { url = await PlantPhotoService.resolve(photo.url) }
    }
}

// MARK: - Swipe-to-delete row (works inside a ScrollView, unlike List swipeActions)

private struct SwipeToDeleteRow<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    private let revealWidth: CGFloat = -72

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.snappy) { offset = 0 }
                HapticFeedback.impact(.rigid)
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 40)
                    .background(Color.brandDanger,
                               in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)
            .accessibilityLabel(Text("Delete"))

            content()
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            let dx = value.translation.width
                            if dx < 0 {
                                offset = max(dx, revealWidth)
                            } else if offset != 0 {
                                offset = min(0, revealWidth + dx)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.snappy) {
                                offset = value.translation.width < revealWidth / 2 ? revealWidth : 0
                            }
                        }
                )
        }
    }
}
