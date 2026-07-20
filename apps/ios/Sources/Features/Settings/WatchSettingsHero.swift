import SwiftUI

// MARK: - "Your watch, live" — the hero of the Apple Watch hub
//
// A hand-drawn Apple Watch (case, crown, side button — no assets) whose
// screen renders EXACTLY what the wrist shows right now, from the same App
// Group pipeline the watch consumes: the widget snapshot plus the catalogs
// that ride every payload push. Honesty law: only real data ever appears
// here — when no snapshot has been written yet, the screen says so instead
// of inventing a demo.
//
// The screen auto-cycles through the owner's chosen pages. The cycle is
// driven by TimelineView(.periodic), not a Timer: the schedule pauses when
// the view is off-screen, so nothing re-renders in the background and the
// scroll stays at 120 fps. With Reduce Motion the cycle stops entirely —
// a static page with tappable dots replaces it.

struct WatchSettingsHero: View {
    /// The live payload assembled from the App Group — nil until the app has
    /// written its first snapshot.
    let payload: WatchPayload?
    /// The pages the wrist would actually render right now, in order,
    /// "today" first — mirrors the watch's own gating (shopping hides when
    /// nothing is pending, map hides without coordinates, …).
    let pageKeys: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var manualIndex = 0
    /// Anchors the auto-cycle so it always opens on Today, like the watch.
    @State private var cycleStart = Date()

    private static let cycleSeconds: TimeInterval = 4

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.22),
                                              Color(red: 0.05, green: 0.07, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))

            if payload == nil || pageKeys.isEmpty {
                deviceFrame { waitingScreen }
                    .padding(.vertical, AppSpacing.xl)
            } else if reduceMotion || pageKeys.count == 1 {
                // Reduce Motion (or a single page): static screen + manual dots.
                VStack(spacing: AppSpacing.base) {
                    deviceFrame { screen(for: pageKeys[safeManualIndex]) }
                    if pageKeys.count > 1 { manualDots }
                }
                .padding(.vertical, AppSpacing.xl)
            } else {
                // The periodic timeline only ticks while the hero is visible,
                // so off-screen the page never re-renders.
                TimelineView(.periodic(from: cycleStart, by: Self.cycleSeconds)) { context in
                    let index = max(0, Int(context.date.timeIntervalSince(cycleStart)
                                           / Self.cycleSeconds)) % pageKeys.count
                    VStack(spacing: AppSpacing.base) {
                        deviceFrame {
                            ZStack {
                                screen(for: pageKeys[index])
                                    .id(pageKeys[index])
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
                            }
                            .animation(.smooth(duration: 0.7), value: index)
                        }
                        dots(current: index)
                    }
                    .padding(.vertical, AppSpacing.xl)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 330)
        // The illustration is one element for VoiceOver: a text alternative
        // describing what the wrist shows, never a soup of tiny labels.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilitySummary))
    }

    private var safeManualIndex: Int {
        min(manualIndex, max(pageKeys.count - 1, 0))
    }

    // MARK: Page dots

    private func dots(current: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(pageKeys.indices, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.4), value: current)
    }

    /// Reduce Motion: the dots become the pager.
    private var manualDots: some View {
        HStack(spacing: 4) {
            ForEach(pageKeys.indices, id: \.self) { i in
                Button {
                    HapticFeedback.impact(.light)
                    manualIndex = i
                } label: {
                    Circle()
                        .fill(i == safeManualIndex ? Color.white : Color.white.opacity(0.28))
                        .frame(width: 7, height: 7)
                        .frame(width: 20, height: 20)   // comfortable tap target
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: The watch hardware (drawn in SwiftUI, no assets)

    private func deviceFrame<Screen: View>(@ViewBuilder screen: () -> Screen) -> some View {
        ZStack(alignment: .trailing) {
            // Case.
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.60), Color(white: 0.36)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 196, height: 236)

            // Display, edge-to-edge black like the real hardware.
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(Color.black)
                .frame(width: 182, height: 222)
                .overlay {
                    screen()
                        .frame(width: 166, height: 206)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
                .padding(.trailing, 7)

            // Digital crown + side button.
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color(white: 0.55))
                    .frame(width: 5, height: 26)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(white: 0.50))
                    .frame(width: 4, height: 34)
            }
            .offset(x: 5)
        }
    }

    // MARK: Screens — every value below comes from the real payload

    @ViewBuilder
    private func screen(for key: String) -> some View {
        if let payload {
            switch key {
            case "today":      todayScreen(payload)
            case "tasks":      tasksScreen(payload)
            case "plants":     plantsScreen(payload)
            case "shopping":   shoppingScreen(payload)
            case "pantry":     pantryScreen(payload)
            case "deliveries": deliveriesScreen(payload)
            case "map":        mapScreen(payload)
            default:           EmptyView()
            }
        }
    }

    /// No snapshot in the App Group yet — say so honestly.
    private var waitingScreen: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(AppFont.scaled(30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.7))
            Text("watch_waiting_title")
                .font(AppFont.scaled(12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("watch_hero_empty")
                .font(AppFont.scaled(10))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: Today — the dashboard the watch opens on

    private func todayScreen(_ payload: WatchPayload) -> some View {
        let snapshot = payload.snapshot
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(verbatim: snapshot.propertyName ?? "PRVIO")
                    .font(AppFont.scaled(12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let streak = payload.streakDays, streak >= 2 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(AppFont.scaled(8, weight: .semibold))
                        Text(verbatim: "\(streak)")
                            .font(AppFont.scaled(10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.orange)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 5),
                                GridItem(.flexible(), spacing: 5)], spacing: 5) {
                metricCell(icon: "checklist",
                           tint: snapshot.overdueTaskCount > 0 ? .orange : .blue,
                           value: snapshot.openTaskCount)
                metricCell(icon: "drop.fill", tint: .cyan, value: snapshot.plantsNeedingWater)
                metricCell(icon: "cart.fill", tint: .orange, value: snapshot.pendingSupplyCount)
                metricCell(icon: "shippingbox.fill", tint: .indigo,
                           value: snapshot.activeDeliveryCount)
            }
            if let temp = payload.weatherTemp, let symbol = payload.weatherSymbol {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(AppFont.scaled(9))
                        .symbolRenderingMode(.multicolor)
                    Text(verbatim: "\(Int(temp.rounded()))°")
                        .font(AppFont.scaled(10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }

    private func metricCell(icon: String, tint: Color, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Image(systemName: icon)
                .font(AppFont.scaled(8, weight: .semibold))
                .foregroundStyle(tint)
            Text(verbatim: "\(value)")
                .font(AppFont.scaled(15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(
            LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    // MARK: Tasks — the real top of the owner's list

    private func tasksScreen(_ payload: WatchPayload) -> some View {
        let open = payload.tasks.filter { !$0.isCompleted }
        return listScreen(title: "watch_tasks", icon: "checklist", tint: .teal) {
            if open.isEmpty {
                allClear
            } else {
                ForEach(open.prefix(3), id: \.id) { task in
                    listRow(icon: (task.isOverdue ?? false)
                                ? "exclamationmark.circle.fill" : "circle",
                            tint: (task.isOverdue ?? false) ? .orange : .white.opacity(0.5),
                            text: task.title)
                }
            }
        }
    }

    // MARK: Plants — who is thirsty right now

    private func plantsScreen(_ payload: WatchPayload) -> some View {
        let thirsty = payload.plants.filter(\.needsWatering)
        return listScreen(title: "watch_plants", icon: "leaf.fill", tint: .green) {
            if thirsty.isEmpty {
                allClear
            } else {
                ForEach(thirsty.prefix(3), id: \.id) { plant in
                    listRow(icon: "drop.fill", tint: .cyan,
                            text: "\(plant.emoji) \(plant.name)")
                }
            }
        }
    }

    // MARK: Shopping — the pending list items

    private func shoppingScreen(_ payload: WatchPayload) -> some View {
        let pending = payload.supplies.filter { !$0.isCompleted }
        return listScreen(title: "watch_shopping", icon: "cart.fill", tint: .orange) {
            ForEach(pending.prefix(3), id: \.id) { item in
                listRow(icon: "circle", tint: .white.opacity(0.5), text: item.name)
            }
        }
    }

    // MARK: Pantry — real stock levels

    private func pantryScreen(_ payload: WatchPayload) -> some View {
        listScreen(title: "watch_pantry", icon: "basket.fill", tint: .orange) {
            ForEach(payload.pantry.prefix(3), id: \.id) { item in
                HStack(spacing: 5) {
                    Text(verbatim: item.name)
                        .font(AppFont.scaled(10, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: "\(item.quantity.formatted(.number.precision(.fractionLength(0...1)))) \(item.unit)")
                        .font(AppFont.scaled(9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 7).padding(.vertical, 6)
                .background(Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // MARK: Deliveries — parcels actually on their way

    private func deliveriesScreen(_ payload: WatchPayload) -> some View {
        listScreen(title: "watch_deliveries", icon: "shippingbox.fill", tint: .indigo) {
            ForEach(payload.deliveries.prefix(2), id: \.id) { parcel in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: deliveryIcon(for: parcel.status))
                            .font(AppFont.scaled(9, weight: .semibold))
                            .foregroundStyle(parcel.status == "out_for_delivery"
                                                ? .orange : .white.opacity(0.6))
                        Text(verbatim: parcel.title)
                            .font(AppFont.scaled(10, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    deliveryStatusLabel(for: parcel.status)
                        .font(AppFont.scaled(8))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(
                    LinearGradient(colors: [Color.indigo.opacity(0.30), Color.indigo.opacity(0.10)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
    }

    // MARK: Map — the property pin (shown only when coordinates exist)

    private func mapScreen(_ payload: WatchPayload) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(AppFont.scaled(26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.purple)
            Text(verbatim: payload.snapshot.propertyName ?? "PRVIO")
                .font(AppFont.scaled(11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("watch_map")
                .font(AppFont.scaled(9))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: Shared screen scaffolding

    private func listScreen<Rows: View>(title: LocalizedStringKey, icon: String, tint: Color,
                                        @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(AppFont.scaled(9, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppFont.scaled(12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            rows()
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }

    private func listRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(tint)
            Text(verbatim: text)
                .font(AppFont.scaled(10, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background(Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var allClear: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(Color.brandSuccess)
            Text("watch_all_good")
                .font(AppFont.scaled(10, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background(Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // Delivery status vocabulary — the same keys the watch itself resolves.
    private func deliveryIcon(for status: String) -> String {
        switch status {
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        default:                 return "shippingbox.fill"
        }
    }

    private func deliveryStatusLabel(for status: String) -> Text {
        switch status {
        case "expected":         return Text("Expected")
        case "out_for_delivery": return Text("Out for delivery")
        case "delivered":        return Text("Delivered")
        case "missed":           return Text("Missed")
        case "returned":         return Text("Returned")
        default:                 return Text(verbatim: status)
        }
    }

    // MARK: VoiceOver — the text alternative for the whole illustration

    private var accessibilitySummary: String {
        guard let payload, !pageKeys.isEmpty else {
            return "\(String(localized: "watch_waiting_title")). \(String(localized: "watch_hero_empty"))"
        }
        let names = pageKeys.map { key -> String in
            switch key {
            case "today":      return String(localized: "watch_page_today")
            case "tasks":      return String(localized: "watch_tasks")
            case "plants":     return String(localized: "watch_plants")
            case "shopping":   return String(localized: "watch_shopping")
            case "pantry":     return String(localized: "watch_pantry")
            case "deliveries": return String(localized: "watch_deliveries")
            case "map":        return String(localized: "watch_map")
            default:           return key
            }
        }
        var summary = String(format: String(localized: "watch_hero_ax %@"),
                             names.formatted(.list(type: .and)))
        let snapshot = payload.snapshot
        summary += ". \(String(localized: "watch_open")): \(snapshot.openTaskCount)"
        if snapshot.overdueTaskCount > 0 {
            summary += ". \(String(localized: "watch_overdue")): \(snapshot.overdueTaskCount)"
        }
        return summary
    }
}
