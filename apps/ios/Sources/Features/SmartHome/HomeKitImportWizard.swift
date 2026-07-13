import SwiftUI
import HomeKit

// MARK: - HomeKit import wizard (Smart Control R1)
//
// The post-connect sheet — presented after a successful HomeKit connect
// from either entry point (the dashboard's Smart Home card / connect row
// and the hub's connect slot), and re-runnable any time from the hub as
// "Importă din HomeKit".
//
// What it shows is REAL, straight from the delegate-mirrored HMHomes:
// - every HomeKit room with its live accessory count,
// - which rooms already have a matching PRVIO space ("Deja legat" — the
//   case/diacritic-insensitive name match used everywhere the two worlds
//   meet; those are never duplicated),
// - the HomeKit cameras found (they surface on the Security Cameras page
//   natively once HomeKit is authorized — the wizard says so instead of
//   pretending to "register" anything),
// - the honest hub guide when the home genuinely lacks a connected home
//   hub (no detection → no scare copy).
//
// One primary action — "Importă tot": each checked, unmatched room becomes
// a PropertyZone through the existing PropertyZoneService.add path (HomeKit
// room membership is the truth; PRVIO mirrors it — accessories surface in
// their space through the same name link SmartHomeService already uses),
// and the room's SpaceKind is inferred by the existing conservative
// heuristic and persisted through setSpaceKind. Every row then reports its
// truthful outcome: created / already linked / skipped / failed — the
// hub createRoom's honest-outcomes discipline, per row.

// MARK: - Outcomes

/// The truthful fate of one wizard row after "Importă tot".
enum HomeKitImportOutcome: Equatable {
    case created
    case alreadyLinked
    case skipped
    case failed(String)

    var labelKey: LocalizedStringKey {
        switch self {
        case .created:       "hub_import_created"
        case .alreadyLinked: "hub_import_already_linked"
        case .skipped:       "hub_import_skipped"
        case .failed:        "hub_import_failed"
        }
    }

    /// The outcome's accent — nil renders as plain secondary text.
    var tint: Color? {
        switch self {
        case .created:                 .brandSuccess
        case .alreadyLinked, .skipped: nil
        case .failed:                  .brandDanger
        }
    }

    /// The truthful failure detail, only for `.failed`.
    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

// MARK: - Wizard sheet

struct HomeKitImportWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService

    private let homeKit = HomeKitService.shared

    /// Rooms the user unchecked — everything importable is included by
    /// default; the set only carries the opt-outs.
    @State private var excludedRooms: Set<UUID> = []
    @State private var isImporting = false
    /// Per-room truthful outcome of the last run; empty until it ran.
    @State private var outcomes: [UUID: HomeKitImportOutcome] = [:]
    @State private var didImport = false

    // MARK: Found rooms (live from the mirrored homes)

    private struct RoomRow: Identifiable {
        let id: UUID
        let name: String
        let accessoryCount: Int
        /// The existing PRVIO space this room already maps to, when one
        /// matches by name — reported, never duplicated.
        let matchedZoneName: String?
    }

    private var roomRows: [RoomRow] {
        homeKit.homes.flatMap { home in
            homeKit.rooms(in: home).map { room in
                RoomRow(id: room.uniqueIdentifier,
                        name: room.name,
                        accessoryCount: home.accessories.filter {
                            $0.room?.uniqueIdentifier == room.uniqueIdentifier
                        }.count,
                        matchedZoneName: matchedZone(named: room.name)?.name)
            }
        }
    }

    private func matchedZone(named name: String) -> PropertyZone? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return zoneService.zones.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(trimmed,
                         options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private var cameraNames: [String] {
        homeKit.cameraAccessories.map(\.name)
    }

    /// Rows that "Importă tot" would actually act on right now.
    private func importableCount(in rows: [RoomRow]) -> Int {
        rows.filter { $0.matchedZoneName == nil && !excludedRooms.contains($0.id) }.count
    }

    // MARK: Body

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    topBar
                    Text("hub_import_subtitle")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if homeKit.isMissingHomeHub {
                        HomeHubGuideRow()
                    }

                    let rows = roomRows
                    roomsSection(rows)
                    camerasSection

                    Spacer(minLength: AppSpacing.sm)
                    primaryAction(rows)

                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Text("hub_import_title")
                .font(AppFont.scaled(26, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                HapticFeedback.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(Text("sh_close"))
        }
    }

    // MARK: Rooms

    @ViewBuilder private func roomsSection(_ rows: [RoomRow]) -> some View {
        sectionHeader("hub_import_rooms_section", count: rows.count)
        if rows.isEmpty {
            (homeKit.homes.isEmpty
                ? Text("hub_import_no_home")
                : Text("hub_import_empty"))
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppSpacing.xxs)
        } else {
            ForEach(rows) { row in
                roomRow(row)
            }
        }
    }

    private func roomRow(_ row: RoomRow) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.md) {
                // Leading control: the opt-out checkbox for importable
                // rooms; matched rooms show the link glyph — nothing to
                // check, they are already a space.
                if row.matchedZoneName != nil {
                    Image(systemName: "link")
                        .font(AppFont.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                } else {
                    checkbox(for: row)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.name)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    (row.accessoryCount == 1
                        ? Text("hub_import_accessory_one")
                        : Text("hub_import_accessory_count \(row.accessoryCount)"))
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: AppSpacing.sm)

                trailingState(for: row)
            }
            // The truthful failure detail, verbatim from the service.
            if let message = outcomes[row.id]?.failureMessage, !message.isEmpty {
                Text(verbatim: message)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.brandDanger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26 + AppSpacing.md)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    /// Trailing truth: the outcome once the import ran; "Deja legat" for
    /// matched rooms before it.
    @ViewBuilder private func trailingState(for row: RoomRow) -> some View {
        if let outcome = outcomes[row.id] {
            Text(outcome.labelKey)
                .font(AppFont.captionStrong)
                .foregroundStyle(outcome.tint.map { AnyShapeStyle($0) }
                                 ?? AnyShapeStyle(.secondary))
        } else if row.matchedZoneName != nil {
            Text("hub_import_already_linked")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func checkbox(for row: RoomRow) -> some View {
        let included = !excludedRooms.contains(row.id)
        return Button {
            HapticFeedback.selection()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                if included {
                    excludedRooms.insert(row.id)
                } else {
                    excludedRooms.remove(row.id)
                }
            }
        } label: {
            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(20))
                .foregroundStyle(included ? Color.accentColor : Color.secondary)
                .frame(width: 26)
        }
        .buttonStyle(.plain)
        .disabled(isImporting || didImport)
        .accessibilityLabel(Text("hub_import_include"))
        .accessibilityValue(Text(verbatim: row.name))
        .accessibilityAddTraits(included ? [.isSelected] : [])
    }

    // MARK: Cameras (informational — they surface natively once authorized)

    @ViewBuilder private var camerasSection: some View {
        let names = cameraNames
        if !names.isEmpty {
            sectionHeader("hub_cameras", count: names.count)
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(names, id: \.self) { name in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "video.fill")
                            .font(AppFont.headline)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26)
                        Text(verbatim: name)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.md)
                    .liquidGlass(cornerRadius: AppRadius.lg)
                    .accessibilityElement(children: .combine)
                }
                Text("hub_import_cameras_note")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.xxs)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Primary action — "Importă tot" → "Gata"

    @ViewBuilder private func primaryAction(_ rows: [RoomRow]) -> some View {
        let importable = importableCount(in: rows)
        if didImport {
            GlassWideButton(icon: "checkmark", label: "hub_import_done") {
                dismiss()
            }
        } else if !rows.isEmpty {
            GlassWideButton(icon: "square.and.arrow.down",
                            label: "hub_import_all",
                            isBusy: isImporting,
                            isEnabled: importable > 0) {
                importAll(rows)
            }
            if importable == 0 {
                Text("hub_import_nothing")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Sequential, truthful import. HomeKit room membership is the truth:
    /// each new zone carries the room's exact name, so the accessories in
    /// that room surface in the space through the same name link every
    /// other surface already uses — nothing is written back to HomeKit.
    private func importAll(_ rows: [RoomRow]) {
        guard !isImporting else { return }
        isImporting = true
        Task { @MainActor in
            defer {
                isImporting = false
                didImport = true
            }
            var result: [UUID: HomeKitImportOutcome] = [:]
            defer { outcomes = result }

            guard let propertyId = propertyService.primary?.id else {
                let message = String(localized: "hub_no_property")
                for row in rows where !excludedRooms.contains(row.id)
                    && row.matchedZoneName == nil {
                    result[row.id] = .failed(message)
                }
                for row in rows where result[row.id] == nil {
                    result[row.id] = excludedRooms.contains(row.id) ? .skipped : .alreadyLinked
                }
                HapticFeedback.error()
                return
            }

            for row in rows {
                if row.matchedZoneName != nil {
                    result[row.id] = .alreadyLinked
                    continue
                }
                if excludedRooms.contains(row.id) {
                    result[row.id] = .skipped
                    continue
                }
                // Re-check against the LIVE zones — a duplicate room name
                // (two homes, same "Living") links to the zone the first
                // row just created instead of duplicating it.
                if matchedZone(named: row.name) != nil {
                    result[row.id] = .alreadyLinked
                    continue
                }
                let now = ISODate.string(from: Date())
                let payload = NewPropertyZone(
                    propertyId: propertyId,
                    name: row.name,
                    icon: "door.left.hand.closed",
                    colorHex: PropertyLayer.property.color.hexString(),
                    layer: PropertyLayer.property.rawValue,
                    healthScore: 100,
                    polygon: [],
                    sortOrder: zoneService.zones.count,
                    createdAt: now,
                    updatedAt: now)
                guard let created = await zoneService.add(payload) else {
                    result[row.id] = .failed(zoneService.error
                        ?? String(localized: "est_create_failed"))
                    continue
                }
                // The existing conservative heuristic classifies the space;
                // only a confident (non-custom) kind is persisted — through
                // the sanctioned setSpaceKind path, best-effort (the zone
                // itself already landed).
                let inferred = SpaceKind.inferred(fromName: created.name,
                                                  icon: created.icon)
                if inferred != .custom {
                    await zoneService.setSpaceKind(inferred, for: created,
                                                   propertyId: propertyId)
                }
                result[row.id] = .created
            }

            let anyFailure = result.values.contains {
                if case .failed = $0 { return true }
                return false
            }
            if anyFailure {
                HapticFeedback.error()
            } else {
                HapticFeedback.success()
            }
        }
    }

    // MARK: Section header (hub style + the honest count)

    private func sectionHeader(_ key: LocalizedStringKey, count: Int) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text(key)
                .font(AppFont.label)
                .kerning(1.1)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(count)")
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.top, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Home hub guide (shared: hub sheet + wizard)

/// The honest hub-state info row: shown ONLY when
/// `HomeKitService.isMissingHomeHub` genuinely detected the absence.
/// Informational glass, with a Learn-more expansion — never a scare
/// banner, never a dead control.
struct HomeHubGuideRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                Image(systemName: "homepod.and.appletv")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("hub_guide_title")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text("hub_guide_body")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if expanded {
                Text("hub_guide_more_body")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26 + AppSpacing.md)
            }
            Button {
                HapticFeedback.selection()
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    expanded.toggle()
                }
            } label: {
                (expanded ? Text("hub_guide_less") : Text("hub_guide_more"))
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .padding(.leading, 26 + AppSpacing.md)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.lg)
        // A container, not a combine: the Learn-more button must stay its
        // own VoiceOver element.
        .accessibilityElement(children: .contain)
    }
}
