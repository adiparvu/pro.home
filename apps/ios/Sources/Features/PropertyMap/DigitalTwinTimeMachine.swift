import SwiftUI

// MARK: - Digital Twin time machine (Faza 4 — "Timp")
//
// The property's dated photos (one per month, from the Photo Journal)
// become a timeline over the same full-bleed view: drag the slider and the
// yard crossfades through its seasons, ending on "Today" — the live aerial
// photo. Read-only by design: it's a lens on the past, not an editor.

struct TwinTimeSnapshot: Identifiable, Equatable {
    let id: String        // "yyyy-MM", or "today"
    let date: Date
    let url: URL?         // nil = the current bundled aerial photo
    let title: String     // localized "July 2026" / "Today"
}

struct TwinTimeMachineOverlay: View {
    let snapshots: [TwinTimeSnapshot]   // ascending by date; last = today
    var onClose: () -> Void

    @State private var index: Double

    init(snapshots: [TwinTimeSnapshot], onClose: @escaping () -> Void) {
        self.snapshots = snapshots
        self.onClose = onClose
        _index = State(initialValue: Double(max(snapshots.count - 1, 0)))
    }

    private var current: TwinTimeSnapshot {
        let i = min(max(Int(index.rounded()), 0), snapshots.count - 1)
        return snapshots[i]
    }

    var body: some View {
        ZStack {
            photo
                .ignoresSafeArea()

            VStack {
                header
                Spacer()
                if snapshots.count > 1 {
                    timeline
                } else {
                    emptyHint
                }
            }
            .padding(AppSpacing.lg)
        }
        .animation(.easeInOut(duration: 0.3), value: current.id)
        .onChange(of: current.id) { _, _ in HapticFeedback.selection() }
    }

    // MARK: - Photo (crossfades between snapshots)

    @ViewBuilder
    private var photo: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                Group {
                    if let url = current.url {
                        StorageImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                ProgressView().tint(.white)
                            }
                        }
                    } else if let ui = UIImage(named: "aerial_property") {
                        Image(uiImage: ui).resizable().scaledToFill()
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .id(current.id)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Header (season chip + close)

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppFont.captionEmphasis)
                Text(seasonLabel)
                    .font(AppFont.captionEmphasis)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))

            Spacer()

            Button {
                HapticFeedback.impact(.light)
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var seasonLabel: LocalizedStringKey {
        if current.url == nil { return "Today" }
        switch Calendar.current.component(.month, from: current.date) {
        case 12, 1, 2:  return "Winter"
        case 3...5:     return "Spring"
        case 6...8:     return "Summer"
        default:        return "Autumn"
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(spacing: 10) {
            Text(current.title)
                .font(AppFont.scaled(17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Slider(value: $index, in: 0...Double(snapshots.count - 1), step: 1)
                .tint(.white)

            HStack {
                Text(snapshots.first?.title ?? "")
                Spacer()
                Text("Today")
            }
            .font(AppFont.label)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(AppSpacing.base)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(.bottom, 30)
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(AppFont.title3)
            Text("Add dated photos to the Photo Journal to travel through time.")
                .font(AppFont.footnote)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(AppSpacing.base)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .padding(.bottom, 30)
    }
}

// MARK: - Snapshot builder

enum TwinTimeline {
    /// One snapshot per month from the journal (the latest photo of each
    /// month), ascending, closed by a "Today" stop on the live aerial photo.
    static func snapshots(from entries: [PhotoJournalEntry]) -> [TwinTimeSnapshot] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "LLLL yyyy"
        fmt.locale = .current

        var byMonth: [String: PhotoJournalEntry] = [:]
        var monthDate: [String: Date] = [:]
        for entry in entries {
            guard let d = entry.takenDate else { continue }
            let comps = cal.dateComponents([.year, .month], from: d)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            if let existing = byMonth[key], let ed = existing.takenDate, ed >= d { continue }
            byMonth[key] = entry
            monthDate[key] = d
        }

        var result: [TwinTimeSnapshot] = byMonth.compactMap { key, entry in
            guard let d = monthDate[key], let url = URL(string: entry.photoUrl) else { return nil }
            return TwinTimeSnapshot(id: key, date: d, url: url,
                                    title: fmt.string(from: d).capitalized)
        }
        .sorted { $0.date < $1.date }

        result.append(TwinTimeSnapshot(id: "today", date: Date(), url: nil,
                                       title: String(localized: "Today")))
        return result
    }
}
