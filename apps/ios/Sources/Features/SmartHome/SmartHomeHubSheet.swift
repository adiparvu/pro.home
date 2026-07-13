import SwiftUI
import HomeKit

// MARK: - Home hub (the dashboard hamburger's destination)
//
// The Apple-Home-style control center presented by the dashboard's top-left
// menu button: one warm-glass sheet that carries the global search (the
// hamburger's previous — and preserved — job), the all-devices list, the
// cameras page, the home's rooms (with honest per-room device counts and
// real room creation), and real HomeKit accessory pairing.
//
// Honesty rules on this surface:
// - The search row opens the EXISTING GlobalSearchSheet unchanged — same
//   sources, same navigation, one tap deeper than before.
// - Room creation writes BOTH authorities when possible — a PropertyZone
//   (the app's own rooms) and an HMHome room (when HomeKit is connected) —
//   and the outcome alert states exactly what succeeded and what failed.
// - "Add device" launches Apple's native pairing flow only when HomeKit is
//   authorized; otherwise the same slot honestly offers "Connect HomeKit".
//   Never a dead control.
struct SmartHomeHubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(AppRouter.self) private var router

    private let smartHome = SmartHomeService.shared
    private let homeKit = HomeKitService.shared

    /// One nested-presentation slot — the same single-`sheet(item:)`
    /// discipline the dashboard itself uses, so presentations never race.
    private enum ActiveSheet: Identifiable {
        case search
        case allDevices
        case room(String)

        var id: String {
            switch self {
            case .search:         "search"
            case .allDevices:     "all-devices"
            case .room(let name): "room-\(name)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet? = nil

    // Create-room flow.
    @State private var showCreateRoom = false
    @State private var newRoomName = ""
    @State private var isCreatingRoom = false

    // Pairing flow.
    @State private var isPairing = false

    /// The truthful outcome of the last hub action (room creation or
    /// pairing), surfaced as an alert.
    private struct HubNotice: Identifiable {
        let id = UUID()
        let titleKey: String
        let message: String
    }

    @State private var notice: HubNotice? = nil

    // MARK: Rooms model

    private struct HubRoom: Identifiable {
        let name: String
        /// The Digital Twin zone's stored icon when the room IS a zone;
        /// provider-only rooms get the neutral room glyph, never a guessed
        /// function icon.
        let icon: String?
        let deviceCount: Int
        var id: String { name }
    }

    /// Every room the home knows about, deduplicated in stable order:
    /// provider rooms (they carry devices) → HomeKit rooms that are still
    /// empty → Digital Twin zones. Counts come from the live device list —
    /// zero is shown honestly, never hidden.
    private var hubRooms: [HubRoom] {
        let devices = smartHome.devices
        var counts: [String: Int] = [:]
        for device in devices {
            if let room = device.room, !room.isEmpty { counts[room, default: 0] += 1 }
        }

        var icons: [String: String] = [:]
        for zone in zoneService.zones {
            let name = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let icon = zone.icon.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !icon.isEmpty, icons[name] == nil { icons[name] = icon }
        }

        var seen = Set<String>()
        var names: [String] = []
        for room in smartHome.rooms where seen.insert(room).inserted {
            names.append(room)
        }
        // HomeKit rooms with no accessories yet — they exist, list them.
        for home in homeKit.homes {
            for room in homeKit.rooms(in: home) {
                let name = room.name
                guard !name.isEmpty, seen.insert(name).inserted else { continue }
                names.append(name)
            }
        }
        for zone in zoneService.zones {
            let name = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            names.append(name)
        }

        return names.map { name in
            HubRoom(name: name, icon: icons[name], deviceCount: counts[name] ?? 0)
        }
    }

    // MARK: Body

    var body: some View {
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    topBar
                    searchRow

                    hubRow(icon: "square.grid.2x2", titleKey: "hub_devices",
                           detail: Text("sh_device_count \(smartHome.devices.count)")) {
                        activeSheet = .allDevices
                    }
                    hubRow(icon: "video.fill", titleKey: "hub_cameras") {
                        openCameras()
                    }

                    sectionHeader("hub_rooms")
                    roomsSection

                    Spacer().frame(height: AppSpacing.xs)
                    addDeviceRow

                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .environment(\.colorScheme, .dark)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $activeSheet, onDismiss: nestedSheetDismissed) { sheet in
            switch sheet {
            case .search:
                // The pre-hub hamburger destination, unchanged — identical
                // search behavior, presented from here instead.
                GlobalSearchSheet()
            case .allDevices:
                SmartHomeDeviceListSheet(kind: nil, room: nil)
            case .room(let name):
                SmartHomeDeviceListSheet(kind: nil, room: name)
            }
        }
        .alert(Text("hub_create_room"), isPresented: $showCreateRoom) {
            TextField("hub_room_name_placeholder", text: $newRoomName)
            Button { createRoom() } label: { Text("hub_create") }
                .disabled(newRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(role: .cancel) { newRoomName = "" } label: { Text("Cancel") }
        }
        .alert(
            Text(LocalizedStringKey(notice?.titleKey ?? "")),
            isPresented: Binding(get: { notice != nil },
                                 set: { if !$0 { notice = nil } }),
            presenting: notice
        ) { _ in
            Button(role: .cancel) {} label: { Text("OK") }
        } message: { presented in
            Text(verbatim: presented.message)
        }
    }

    /// GlobalSearchSheet navigates by parking the route in
    /// `router.pendingRoute` and dismissing itself. When that happens the
    /// hub must clear the stage too, so the dashboard's own `onDismiss`
    /// can drain the route onto a visible stack — the exact handoff the
    /// hamburger's direct search presentation used to get for free.
    private func nestedSheetDismissed() {
        if router.pendingRoute != nil { dismiss() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Text("hub_title")
                .font(AppFont.scaled(26, weight: .light))
                .foregroundStyle(Color.smartTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                HapticFeedback.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.smartTextPrimary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(Text("sh_close"))
        }
    }

    // MARK: Search row (the preserved hamburger job, top of the hub)

    private var searchRow: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        return Button {
            HapticFeedback.impact(.light)
            activeSheet = .search
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.smartTextSecondary)
                Text("hub_search")
                    .font(AppFont.scaled(16))
                    .foregroundStyle(Color.smartTextSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(SmartCardPressStyle())
        .background {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.smartGlassFill)
        }
        .clipShape(shape)
        .accessibilityHint(Text("hub_search_hint"))
    }

    // MARK: Rooms section

    @ViewBuilder private var roomsSection: some View {
        if hubRooms.isEmpty {
            Text("hub_rooms_empty")
                .font(AppFont.caption)
                .foregroundStyle(Color.smartTextSecondary)
                .padding(.horizontal, AppSpacing.xxs)
        } else {
            ForEach(hubRooms) { room in
                hubRow(icon: room.icon ?? "door.left.hand.closed",
                       title: Text(verbatim: room.name),
                       detail: Text("sh_device_count \(room.deviceCount)")) {
                    activeSheet = .room(room.name)
                }
            }
        }

        hubRow(icon: "plus", titleKey: "hub_create_room",
               showsChevron: false, showsProgress: isCreatingRoom) {
            showCreateRoom = true
        }
        .disabled(isCreatingRoom)
    }

    // MARK: Add device / Connect HomeKit (never a dead button)

    @ViewBuilder private var addDeviceRow: some View {
        if smartHome.homeKitAuthorized {
            hubRow(icon: "plus.circle", titleKey: "hub_add_device",
                   showsChevron: false, showsProgress: isPairing) {
                startPairing()
            }
            .disabled(isPairing)
        } else {
            // Pairing needs HomeKit first — the same slot honestly offers
            // the real permission flow instead of a control that can't work.
            hubRow(icon: "homekit", titleKey: "sh_connect_homekit",
                   showsChevron: false) {
                smartHome.connectHomeKit()
            }
        }
    }

    // MARK: Actions

    private func openCameras() {
        // Cameras is a pushed content page (AppRoute.cameras) — park the
        // route and clear the stage, exactly like the search shortcuts do;
        // the dashboard's onDismiss drains it onto the visible stack.
        router.pendingRoute = .cameras
        dismiss()
    }

    private func startPairing() {
        // (The row's tap haptic already fired in hubRow.)
        isPairing = true
        Task { @MainActor in
            defer { isPairing = false }
            do {
                try await homeKit.startPairing(in: homeKit.primaryHome)
                HapticFeedback.success()
            } catch {
                // Backing out of Apple's sheet is a choice, not a failure.
                if let hkError = error as? HMError, hkError.code == .operationCancelled { return }
                HapticFeedback.error()
                notice = HubNotice(
                    titleKey: "hub_add_device",
                    message: String(format: String(localized: "hub_pairing_failed"),
                                    error.localizedDescription))
            }
        }
    }

    /// Creates the room in BOTH authorities: the in-app PropertyZone (always
    /// attempted) and the HomeKit room (when a home is connected). Partial
    /// success is reported truthfully — the alert says exactly which side
    /// landed and why the other failed.
    private func createRoom() {
        let name = newRoomName.trimmingCharacters(in: .whitespacesAndNewlines)
        newRoomName = ""
        guard !name.isEmpty else { return }
        guard !hubRooms.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            notice = HubNotice(titleKey: "hub_create_room",
                               message: String(localized: "hub_room_exists"))
            return
        }
        isCreatingRoom = true
        Task { @MainActor in
            defer { isCreatingRoom = false }

            // 1) The in-app zone — PRVIO's own room authority. A named zone
            //    without geometry is valid (the shape can be drawn later in
            //    the Digital Twin); it immediately feeds the dashboard's
            //    room chips and this hub's list.
            var zoneOK = false
            var zoneFailure: String? = nil
            if let propertyId = propertyService.primary?.id {
                let now = ISODate.string(from: Date())
                let payload = NewPropertyZone(
                    propertyId: propertyId,
                    name: name,
                    icon: "door.left.hand.closed",
                    colorHex: PropertyLayer.property.color.hexString(),
                    layer: PropertyLayer.property.rawValue,
                    healthScore: 100,
                    polygon: [],
                    sortOrder: zoneService.zones.count,
                    createdAt: now,
                    updatedAt: now)
                zoneOK = await zoneService.add(payload) != nil
                if !zoneOK { zoneFailure = zoneService.error }
            } else {
                zoneFailure = String(localized: "hub_no_property")
            }

            // 2) The HomeKit room, when a home is connected.
            var homeKitAttempted = false
            var homeKitOK = false
            var homeKitFailure: String? = nil
            if smartHome.homeKitAuthorized, let home = homeKit.primaryHome {
                homeKitAttempted = true
                do {
                    try await homeKit.addRoom(name: name, to: home)
                    homeKitOK = true
                } catch {
                    homeKitFailure = error.localizedDescription
                }
            }

            if zoneOK && (homeKitOK || !homeKitAttempted) {
                HapticFeedback.success()
            } else {
                HapticFeedback.error()
            }
            notice = HubNotice(titleKey: "hub_create_room",
                               message: creationMessage(
                                   zoneOK: zoneOK, zoneFailure: zoneFailure,
                                   homeKitAttempted: homeKitAttempted,
                                   homeKitOK: homeKitOK,
                                   homeKitFailure: homeKitFailure))
        }
    }

    private func creationMessage(zoneOK: Bool, zoneFailure: String?,
                                 homeKitAttempted: Bool, homeKitOK: Bool,
                                 homeKitFailure: String?) -> String {
        switch (zoneOK, homeKitAttempted, homeKitOK) {
        case (true, true, true):
            return String(localized: "hub_room_created_full")
        case (true, false, _):
            return String(localized: "hub_room_created_app")
        case (true, true, false):
            return String(format: String(localized: "hub_room_partial_homekit"),
                          homeKitFailure ?? "")
        case (false, _, true):
            return String(format: String(localized: "hub_room_partial_zone"),
                          zoneFailure ?? "")
        default:
            return String(format: String(localized: "hub_room_failed"),
                          zoneFailure ?? homeKitFailure ?? "")
        }
    }

    // MARK: Row chrome

    private func hubRow(icon: String, titleKey: LocalizedStringKey,
                        detail: Text? = nil, showsChevron: Bool = true,
                        showsProgress: Bool = false,
                        action: @escaping () -> Void) -> some View {
        hubRow(icon: icon, title: Text(titleKey), detail: detail,
               showsChevron: showsChevron, showsProgress: showsProgress,
               action: action)
    }

    private func hubRow(icon: String, title: Text,
                        detail: Text? = nil, showsChevron: Bool = true,
                        showsProgress: Bool = false,
                        action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        return Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.smartAmber)
                    .frame(width: 26)
                title
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.smartTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.sm)
                if showsProgress {
                    ProgressView()
                        .tint(Color.smartAmber)
                } else {
                    if let detail {
                        detail
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.smartTextSecondary)
                    }
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.smartTextSecondary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(SmartCardPressStyle())
        .background {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.smartGlassFill)
        }
        .clipShape(shape)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .kerning(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Color.smartTextSecondary)
            .padding(.top, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.xxs)
            .accessibilityAddTraits(.isHeader)
    }
}
