import SwiftUI
import MapKit

// MARK: - Pages

enum WatchPage: Hashable {
    case today, tasks, plants, shopping, pantry, deliveries, map
}

// MARK: - Double tap
//
// The two-finger double-tap fires each page's PRIMARY action without
// touching the screen. watchOS 11+ only; earlier systems simply ignore it.
extension View {
    @ViewBuilder
    func primaryDoubleTap() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

// MARK: - Wrist design language
//
// The dialect the whole watch app speaks — Athlytic's dense dashboard,
// Gentler Streak's soft gradient cards, Things' rounded typographic
// hierarchy, Waterllama's act-then-celebrate feedback. One place, so every
// page stays coherent.

enum WatchDesign {
    /// Soft card fill: the domain colour breathing through dark glass.
    static func cardFill(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.32), color.opacity(0.10)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func score(_ value: Int) -> Color {
        switch value {
        case 80...:   return .green
        case 60..<80: return .yellow
        default:      return .orange
        }
    }
}

/// The soft rounded card every module sits in. On watchOS 26 it wears real
/// Liquid Glass (tinted); earlier systems keep the gradient fill — one
/// authority, so the whole app upgrades the day the target does.
private struct WatchCard<Content: View>: View {
    var tint: Color = .gray
    @ViewBuilder var content: Content

    var body: some View {
        if #available(watchOS 26.0, *) {
            padded.glassEffect(.regular.tint(tint.opacity(0.3)),
                               in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            padded.background(WatchDesign.cardFill(tint),
                              in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var padded: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Staggered entrance — cards breathe in one after another. Sits out
/// entirely under Reduce Motion.
private struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.5).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

// MARK: - Root: vertical pages, or the sync prompt

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var selection: WatchPage = .today

    /// Default order when the phone hasn't sent a preference yet.
    private static let defaultOrder = ["tasks", "plants", "shopping", "pantry", "deliveries", "map"]

    /// The payload's page order, deduped defensively — a payload cached by
    /// an older phone build can carry duplicate keys, and two ForEach rows
    /// with the same identity is undefined behavior (crashes on device).
    private static func orderedPages(_ payload: WatchPayload) -> [String] {
        var seen = Set<String>()
        return (payload.pageOrder ?? defaultOrder).filter { seen.insert($0).inserted }
    }

    /// Advertising an NSUserActivity whose type isn't declared in the
    /// built Info.plist throws NSInternalInconsistencyException at first
    /// render on a real watch ("opens and instantly exits"). The plist now
    /// declares it, and this runtime check makes the crash impossible even
    /// if a build configuration ever drops the key again.
    private static let handoffDeclared: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String])?
            .contains("com.prvio.page") == true

    var body: some View {
        if let payload = store.payload {
            pages(payload)
                .tabViewStyle(.verticalPage)
                .onOpenURL { url in
                    // Complication taps: prvio://tasks, prvio://plants, …
                    switch url.host {
                    case "tasks":                  selection = .tasks
                    case "plants":                 selection = .plants
                    case "shopping", "supplies":   selection = .shopping
                    case "pantry":                 selection = .pantry
                    case "deliveries", "packages": selection = .deliveries
                    default:                       selection = .today
                    }
                }
        } else {
            waiting
        }
    }

    @ViewBuilder
    private func pages(_ payload: WatchPayload) -> some View {
        let tabs = TabView(selection: $selection) {
            TodayGlance(payload: payload, selection: $selection)
                .tag(WatchPage.today)
            // The owner's pages, in the owner's order (chosen on the
            // iPhone). Data-gating stays: an enabled page with nothing
            // to show still steps aside.
            ForEach(Self.orderedPages(payload), id: \.self) { key in
                page(for: key, payload: payload)
            }
        }
        if Self.handoffDeclared {
            // Handoff: raise the iPhone and land on the page you were
            // reading here — the phone router already speaks this activity.
            tabs.userActivity("com.prvio.page") { activity in
                activity.isEligibleForHandoff = true
                activity.userInfo = ["tab": Self.handoffKey(for: selection)]
            }
        } else {
            tabs
        }
    }

    @ViewBuilder
    private func page(for key: String, payload: WatchPayload) -> some View {
        switch key {
        case "tasks":
            TasksPage(tasks: payload.tasks)
                .tag(WatchPage.tasks)
        case "plants":
            PlantsPage(plants: payload.plants)
                .tag(WatchPage.plants)
        case "shopping":
            if payload.supplies.contains(where: { !$0.isCompleted }) {
                ShoppingPage(supplies: payload.supplies)
                    .tag(WatchPage.shopping)
            }
        case "pantry":
            if !payload.pantry.isEmpty {
                PantryPage(items: payload.pantry)
                    .tag(WatchPage.pantry)
            }
        case "deliveries":
            if !payload.deliveries.isEmpty {
                DeliveriesPage(deliveries: payload.deliveries)
                    .tag(WatchPage.deliveries)
            }
        case "map":
            if let lat = payload.latitude, let lon = payload.longitude {
                PropertyMapPage(latitude: lat, longitude: lon,
                                name: payload.snapshot.propertyName)
                    .tag(WatchPage.map)
            }
        default:
            EmptyView()
        }
    }

    private static func handoffKey(for page: WatchPage) -> String {
        switch page {
        case .today:      return "home"
        case .tasks:      return "tasks"
        case .plants:     return "plants"
        case .shopping:   return "supplies"
        case .pantry:     return "pantry"
        case .deliveries: return "deliveries"
        case .map:        return "map"
        }
    }

    private var waiting: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_waiting_title")
                .font(.system(.headline, design: .rounded))
            Text("watch_waiting_msg")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Page 1: Today (the dashboard)

private struct TodayGlance: View {
    let payload: WatchPayload
    @Binding var selection: WatchPage

    private var snapshot: PRVIOWidgetSnapshot { payload.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    hero.entrance(0)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        metric(count: snapshot.openTaskCount, label: "watch_open",
                               icon: "checklist", tint: .blue,
                               urgent: snapshot.overdueTaskCount > 0, page: .tasks)
                            .entrance(1)
                        metric(count: snapshot.plantsNeedingWater, label: "watch_water",
                               icon: "drop.fill", tint: .cyan, urgent: false, page: .plants)
                            .entrance(2)
                        metric(count: snapshot.activeDeliveryCount, label: "watch_deliveries",
                               icon: "shippingbox.fill", tint: .indigo, urgent: false,
                               page: .deliveries)
                            .entrance(3)
                        metric(count: snapshot.pendingSupplyCount, label: "watch_shopping",
                               icon: "cart.fill", tint: .orange, urgent: false, page: .shopping)
                            .entrance(4)
                    }

                    if let session = store.activeSession {
                        sessionCard(session).entrance(1)
                    }

                    if let temp = payload.weatherTemp, let symbol = payload.weatherSymbol {
                        weatherCard(temp: temp, symbol: symbol).entrance(5)
                    }

                    if snapshot.unreadMessages > 0 {
                        unreadRow(snapshot.unreadMessages).entrance(5)
                    }

                    if let insight = payload.insightTitle {
                        insightCard(title: insight, body: payload.insightBody)
                            .entrance(7)
                    }

                    if let critical = snapshot.criticalTaskTitle {
                        focusCard(icon: "exclamationmark.circle.fill", tint: .red,
                                  title: critical, sub: nil)
                            .entrance(6)
                    } else if let next = snapshot.nextMaintenanceTitle {
                        focusCard(icon: "wrench.and.screwdriver.fill", tint: .gray,
                                  title: next, sub: snapshot.nextMaintenanceDue)
                            .entrance(6)
                    }

                    freshnessFooter
                }
            }
            .navigationTitle(Text(verbatim: "PRVIO"))
            .containerBackground(Color.blue.gradient.opacity(0.25), for: .navigation)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Ask the phone for a fresh payload over the live channel.
                    Button {
                        store.requestRefresh()
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing)
                    .accessibilityLabel(Text("watch_refresh"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Dictate a message for the house chat — the phone sends
                    // the real one through the same queue notification
                    // replies use.
                    TextFieldLink(prompt: Text("watch_chat_prompt")) {
                        Image(systemName: "message")
                            .accessibilityLabel(Text("watch_chat_send"))
                    } onSubmit: { value in
                        store.sendChatMessage(value)
                    }
                }
            }
        }
    }

    /// The running maintenance session — live elapsed, tap to open.
    private func sessionCard(_ session: WatchStore.WorkSession) -> some View {
        Button { showSession = true } label: {
            WatchCard(tint: .teal) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Text(session.startedAt, style: .timer)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSession) { WorkSessionView() }
    }

    @State private var showSession = false

    /// Trust is knowing how old the data is — stale info must say so.
    private var freshnessFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 8))
            Text("watch_updated")
                .font(.system(size: 9))
            Text(snapshot.updatedAt, format: .relative(presentation: .named))
                .font(.system(size: 9))
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    @Environment(WatchStore.self) private var store

    // Athlytic hero: the health ring fills on arrival, the name sits beside it.
    private var hero: some View {
        HStack(spacing: 10) {
            if let score = snapshot.propertyHealthScore {
                HealthRing(score: score)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.propertyName ?? "PRVIO")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let streak = payload.streakDays, streak >= 2 {
                    // The house streak — consecutive verified all-clear days.
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, value: streak)
                        Text(String(format: String(localized: "watch_streak"), streak))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                    }
                } else if snapshot.propertyHealthScore != nil {
                    Text("watch_health")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private func metric(count: Int, label: LocalizedStringKey, icon: String,
                        tint: Color, urgent: Bool, page: WatchPage) -> some View {
        Button {
            selection = page
        } label: {
            WatchCard(tint: urgent ? .red : tint) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(urgent ? .red : tint)
                        if urgent {
                            Circle().fill(.red).frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(verbatim: "\(count)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Apple Weather at the property, with the garden advisory when there is
    /// one — and the attribution the WeatherKit terms require.
    private func weatherCard(temp: Double, symbol: String) -> some View {
        WatchCard(tint: .cyan) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.multicolor)
                    Text(verbatim: "\(Int(temp.rounded()))°")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    if let lo = payload.weatherLo, let hi = payload.weatherHi {
                        Text(verbatim: "\(Int(lo.rounded()))°–\(Int(hi.rounded()))°")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                if let advisory = payload.weatherAdvisory {
                    HStack(spacing: 4) {
                        Image(systemName: advisory == "frost" ? "snowflake" : "cloud.rain.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(advisory == "frost" ? "watch_adv_frost" : "watch_adv_rain")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(.orange)
                }
                Text(verbatim: " Apple Weather")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func unreadRow(_ count: Int) -> some View {
        WatchCard(tint: .blue) {
            HStack(spacing: 6) {
                Image(systemName: "message.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(verbatim: "\(count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("watch_unread")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        // Redacted on the Always-On dim state — messages aren't for
        // whoever walks past a resting wrist.
        .privacySensitive()
    }

    /// The ProactiveEngine's freshest insight — generated on the iPhone,
    /// pushed in the payload, readable with the phone out of reach.
    private func insightCard(title: String, body: String?) -> some View {
        WatchCard(tint: .purple) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                    if let body, !body.isEmpty {
                        Text(body)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func focusCard(icon: String, tint: Color, title: String, sub: String?) -> some View {
        WatchCard(tint: tint) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint == .gray ? .secondary : tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.footnote, design: .rounded))
                        .lineLimit(2)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .privacySensitive()
    }
}

/// The property's health as a ring that fills when the dashboard arrives.
private struct HealthRing: View {
    let score: Int
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Gauge(value: shown, in: 0...100) {
            Image(systemName: "house.fill")
        } currentValueLabel: {
            Text(verbatim: "\(Int(shown))")
                .font(.system(.body, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [WatchDesign.score(score).opacity(0.55),
                                WatchDesign.score(score)]))
        .frame(width: 54, height: 54)
        .onAppear {
            if reduceMotion {
                shown = Double(score)
            } else {
                withAnimation(.spring(duration: 1.1)) { shown = Double(score) }
            }
        }
        .accessibilityLabel(Text("watch_health"))
        .accessibilityValue(Text(verbatim: "\(score)%"))
    }
}

// MARK: - Acting rows (Waterllama feedback: fill, bounce, then leave)

/// The leading action symbol: tap → it fills and bounces, a beat later the
/// real action fires and the row animates out. The pause is the celebration.
private struct ActingSymbol: View {
    let idle: String
    let acted: String
    let tint: Color
    let label: LocalizedStringKey
    /// Marks this control as the page's double-tap primary action.
    var isPrimary = false
    let action: () -> Void

    @State private var didAct = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isPrimary {
            core.primaryDoubleTap()
        } else {
            core
        }
    }

    private var core: some View {
        Button {
            guard !didAct else { return }
            didAct = true
            if reduceMotion {
                action()
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(380))
                    action()
                }
            }
        } label: {
            Image(systemName: didAct ? acted : idle)
                .font(.system(size: 17, weight: didAct ? .semibold : .light))
                .foregroundStyle(didAct ? tint : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: didAct)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Page 2: Tasks

private struct TasksPage: View {
    let tasks: [TaskCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var open: [TaskCatalogEntry] {
        // Overdue first, then the rest, capped for wrist reading.
        let pending = tasks.filter { !$0.isCompleted }
        return Array((pending.filter { $0.isOverdue == true }
                      + pending.filter { $0.isOverdue != true }).prefix(12))
    }

    var body: some View {
        NavigationStack {
            Group {
                if open.isEmpty {
                    AllClearView(icon: "checkmark.circle")
                } else {
                    List(open, id: \.id) { task in
                        // Symbol acts on the spot; the row opens the detail —
                        // the Things split, no accidental completes.
                        NavigationLink(value: task.id) {
                            HStack(spacing: 8) {
                                ActingSymbol(idle: "circle",
                                             acted: "checkmark.circle.fill",
                                             tint: task.isOverdue == true ? .red : .blue,
                                             label: "watch_complete",
                                             isPrimary: task.id == open.first?.id) {
                                    withAnimation(.snappy) { store.completeTask(task.id) }
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(task.title)
                                        .font(.system(.footnote, design: .rounded))
                                        .lineLimit(2)
                                    if task.isOverdue == true {
                                        Text("watch_overdue")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(task.isOverdue == true ? .red : .blue))
                        )
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let task = open.first(where: { $0.id == id }) {
                            TaskDetail(task: task)
                        }
                    }
                }
            }
            .navigationTitle(Text("watch_tasks"))
            .containerBackground(Color.blue.gradient.opacity(0.3), for: .navigation)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Dictate a task straight from the wrist — the phone
                    // creates the real one on its next beat.
                    TextFieldLink(prompt: Text("watch_new_task_prompt")) {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text("New Task"))
                    } onSubmit: { value in
                        withAnimation(.snappy) { store.createTask(value) }
                    }
                }
            }
        }
    }
}

private struct TaskDetail: View {
    let task: TaskCatalogEntry
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showSession = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if task.isOverdue == true {
                    Label { Text("watch_overdue") } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                }

                Text(task.title)
                    .font(.system(.headline, design: .rounded))

                Button {
                    store.completeTask(task.id)
                    dismiss()
                } label: {
                    Label { Text("watch_complete") } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .primaryDoubleTap()

                // Time the work: start a session, get on with the job.
                Button {
                    if store.activeSession?.taskId != task.id {
                        store.startSession(taskId: task.id, title: task.title)
                    }
                    showSession = true
                } label: {
                    Label { Text(store.activeSession?.taskId == task.id
                                 ? "watch_session_open" : "watch_session_start") } icon: {
                        Image(systemName: "timer")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(Color.blue.gradient.opacity(0.3), for: .navigation)
        .sheet(isPresented: $showSession) { WorkSessionView() }
    }
}

// MARK: - Work session (maintenance timer)

private struct WorkSessionView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Minute ticker for the quarter-hour haptic — fires only while this
    /// screen is up; the elapsed display itself needs no timer at all
    /// (Text(style: .timer) is system-driven).
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        if let session = store.activeSession {
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.teal)
                        .symbolEffect(.pulse)
                    Text(session.title)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(session.startedAt, style: .timer)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Button {
                        store.endSession(completingTask: true)
                        dismiss()
                    } label: {
                        Label { Text("watch_complete") } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .primaryDoubleTap()

                    Button {
                        store.endSession(completingTask: false)
                        dismiss()
                    } label: {
                        Label { Text("watch_session_end") } icon: {
                            Image(systemName: "stop.circle")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .onReceive(minuteTick) { _ in
                // A quiet pulse every quarter hour keeps time honest while
                // hands are busy — screen-on only, by design.
                let minutes = Int(Date().timeIntervalSince(session.startedAt) / 60)
                if minutes > 0, minutes % 15 == 0 {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        } else {
            AllClearView(icon: "timer")
                .onAppear { dismiss() }
        }
    }
}

// MARK: - Page 3: Plants

private struct PlantsPage: View {
    let plants: [PlantCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var thirsty: [PlantCatalogEntry] { plants.filter(\.needsWatering) }

    var body: some View {
        NavigationStack {
            Group {
                if thirsty.isEmpty {
                    AllClearView(icon: "leaf")
                } else {
                    List(thirsty, id: \.id) { plant in
                        NavigationLink(value: plant.id) {
                            HStack(spacing: 6) {
                                ActingSymbol(idle: "drop",
                                             acted: "drop.fill",
                                             tint: .cyan,
                                             label: "watch_water_now",
                                             isPrimary: thirsty.count == 1
                                                        && plant.id == thirsty.first?.id) {
                                    withAnimation(.snappy) { store.waterPlant(plant.id) }
                                }
                                Text(plant.emoji)
                                Text(plant.name)
                                    .font(.system(.footnote, design: .rounded))
                                    .lineLimit(1)
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(.cyan))
                        )
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let plant = thirsty.first(where: { $0.id == id }) {
                            PlantDetail(plant: plant)
                        }
                    }
                }
            }
            .navigationTitle(Text("watch_plants"))
            .containerBackground(Color.green.gradient.opacity(0.3), for: .navigation)
            .toolbar {
                if thirsty.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        // With several thirsty plants, double-tap waters all.
                        Button {
                            withAnimation(.snappy) { store.waterAllPlants() }
                        } label: {
                            Image(systemName: "drop.fill")
                        }
                        .accessibilityLabel(Text("watch_water_all"))
                        .primaryDoubleTap()
                    }
                }
            }
        }
    }
}

private struct PlantDetail: View {
    let plant: PlantCatalogEntry
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(plant.emoji)
                    .font(.system(size: 44))
                Text(plant.name)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)

                Button {
                    store.waterPlant(plant.id)
                    dismiss()
                } label: {
                    Label { Text("watch_water_now") } icon: {
                        Image(systemName: "drop.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .primaryDoubleTap()
            }
            .frame(maxWidth: .infinity)
        }
        .containerBackground(Color.green.gradient.opacity(0.3), for: .navigation)
    }
}

// MARK: - Page 4: Shopping

private struct ShoppingPage: View {
    let supplies: [SupplyCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var pending: [SupplyCatalogEntry] {
        Array(supplies.filter { !$0.isCompleted }.prefix(15))
    }

    var body: some View {
        NavigationStack {
            Group {
                if pending.isEmpty {
                    AllClearView(icon: "cart")
                } else {
                    List(pending, id: \.id) { item in
                        HStack(spacing: 8) {
                            ActingSymbol(idle: "circle",
                                         acted: "checkmark.circle.fill",
                                         tint: .orange,
                                         label: "watch_tap_check",
                                         isPrimary: item.id == pending.first?.id) {
                                withAnimation(.snappy) { store.checkSupply(item.id) }
                            }
                            Text(item.name)
                                .font(.system(.footnote, design: .rounded))
                                .lineLimit(2)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(.orange))
                        )
                    }
                }
            }
            .navigationTitle(Text("watch_shopping"))
            .containerBackground(Color.orange.gradient.opacity(0.3), for: .navigation)
        }
    }
}

// MARK: - Page 4b: Pantry (consume from the wrist)

private struct PantryPage: View {
    let items: [PantryCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var stocked: [PantryCatalogEntry] { Array(items.prefix(15)) }

    var body: some View {
        NavigationStack {
            Group {
                if stocked.isEmpty {
                    AllClearView(icon: "basket")
                } else {
                    List(stocked, id: \.id) { item in
                        PantryRow(item: item,
                                  isPrimary: item.id == stocked.first?.id) {
                            store.consumePantry(item.id)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(.green))
                        )
                    }
                }
            }
            .navigationTitle(Text("watch_pantry"))
            .containerBackground(Color.green.gradient.opacity(0.25), for: .navigation)
        }
    }
}

/// Repeatable consume row — unlike the one-shot ActingSymbol, stock can be
/// consumed again and again; the icon bounces on every unit.
private struct PantryRow: View {
    let item: PantryCatalogEntry
    var isPrimary = false
    let consume: () -> Void

    private var quantityLabel: String {
        let qty = item.quantity
        let number = qty == qty.rounded() ? String(Int(qty)) : String(format: "%.1f", qty)
        return "\(number) \(item.unit)"
    }

    var body: some View {
        HStack(spacing: 8) {
            consumeButton
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(.footnote, design: .rounded))
                    .lineLimit(1)
                Text(verbatim: quantityLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.quantity <= 0 ? .red : .secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var consumeButton: some View {
        if isPrimary {
            core.primaryDoubleTap()
        } else {
            core
        }
    }

    private var core: some View {
        Button {
            withAnimation(.snappy) { consume() }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 17))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.quantity > 0 ? .green : .secondary)
                .symbolEffect(.bounce, value: item.quantity)
        }
        .buttonStyle(.plain)
        .disabled(item.quantity <= 0)
        .accessibilityLabel(Text("watch_consume_one"))
        .accessibilityValue(Text(verbatim: quantityLabel))
    }
}

// MARK: - Page 5: Deliveries (glanceable, read-only)

private struct DeliveriesPage: View {
    let deliveries: [DeliveryCatalogEntry]

    var body: some View {
        NavigationStack {
            List(deliveries.prefix(10), id: \.id) { parcel in
                NavigationLink(value: parcel.id) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: DeliveryGlyphs.icon(for: parcel.status))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(parcel.status == "out_for_delivery" ? .orange : .secondary)
                            Text(parcel.title)
                                .font(.system(.footnote, design: .rounded))
                                .lineLimit(2)
                        }
                        DeliveryGlyphs.statusLabel(for: parcel.status)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WatchDesign.cardFill(.indigo))
                )
            }
            .navigationDestination(for: UUID.self) { id in
                if let parcel = deliveries.first(where: { $0.id == id }) {
                    DeliveryDetail(parcel: parcel)
                }
            }
            .navigationTitle(Text("watch_deliveries"))
            .containerBackground(Color.cyan.gradient.opacity(0.3), for: .navigation)
        }
    }
}

private struct DeliveryDetail: View {
    let parcel: DeliveryCatalogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: DeliveryGlyphs.icon(for: parcel.status))
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(parcel.status == "out_for_delivery" ? .orange : .secondary)

                Text(parcel.title)
                    .font(.system(.headline, design: .rounded))

                DeliveryGlyphs.statusLabel(for: parcel.status)
                    .font(.footnote.weight(.semibold))

                if let carrier = parcel.carrier, !carrier.isEmpty {
                    Text(verbatim: carrier)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let eta = parcel.eta, !eta.isEmpty {
                    Text(verbatim: eta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(Color.cyan.gradient.opacity(0.3), for: .navigation)
    }
}

// MARK: - Page 6: Property map (the twin on the wrist)
//
// MapKit's native watch map: crown and pan gestures come free, the property
// pin wears the brand. Coordinates ride the payload, so the map centers
// correctly even offline (tiles need connectivity; the pin does not).

private struct PropertyMapPage: View {
    let latitude: Double
    let longitude: Double
    let name: String?

    @State private var position: MapCameraPosition

    init(latitude: Double, longitude: Double, name: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                Annotation(name ?? "PRVIO",
                           coordinate: CLLocationCoordinate2D(latitude: latitude,
                                                              longitude: longitude)) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: 30, height: 30)
                        Image(systemName: "house.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.blue))
                    }
                }
            }
            .navigationTitle(Text("watch_map"))
        }
    }
}

// MARK: - Delivery glyphs (shared row/detail vocabulary)

enum DeliveryGlyphs {
    static func icon(for status: String) -> String {
        switch status {
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        default:                 return "shippingbox.fill"
        }
    }

    // The same keys the iPhone's Delivery.statusLabel resolves.
    static func statusLabel(for status: String) -> Text {
        switch status {
        case "expected":         return Text("Expected")
        case "out_for_delivery": return Text("Out for delivery")
        case "delivered":        return Text("Delivered")
        case "missed":           return Text("Missed")
        case "returned":         return Text("Returned")
        default:                 return Text(verbatim: status)
        }
    }
}

// MARK: - Shared empty state

private struct AllClearView: View {
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_all_good")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
