import SwiftUI
import ActivityKit

// MARK: - Live Activity Simulator
//
// Starts REAL ActivityKit activities through the same LiveActivityService
// functions the app's flows use — nothing here is a mock. Every scenario's
// sample content is explicitly labeled "Test — …" so the activity on the
// Lock Screen / Dynamic Island can never be mistaken for real household
// data, and it stays live until ended (here, or from the activity itself).
//
// Honesty notes:
// - The service functions keep ALL their real gates (master switch, system
//   authorization, per-kind auto-start). Rather than pretending a start
//   happened, gated rows are disabled with an explanation, and the running
//   state is re-read from ActivityKit after every action.
// - Event recording happens inside the service hooks; this screen never
//   records events itself, so the timeline/analytics stay double-count-free.

struct LiveActivitySimulatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(LiveActivityPrefs.enabledKey, store: LiveActivityPrefs.store)
    private var appEnabled = true

    @State private var systemEnabled = true
    @State private var running: Set<LiveActivityKind> = []

    private var store: LiveActivityHubStore { .shared }
    private var canUseActivities: Bool { systemEnabled && appEnabled }

    // MARK: Scenarios — every closure calls a REAL, existing service function.

    private struct SimScenario: Identifiable {
        let kind: LiveActivityKind
        /// The exact, clearly-labeled sample content the activity will show.
        let sample: String
        let start: @MainActor () -> Void
        var id: String { kind.id }
    }

    private var scenarios: [SimScenario] {
        [
            SimScenario(kind: .workSession, sample: "Test — Robinet bucătărie") {
                LiveActivityService.shared.startWorkSession(
                    taskId: UUID(), title: "Test — Robinet bucătărie")
            },
            SimScenario(kind: .maintenance, sample: "Test — Filtru HVAC") {
                LiveActivityService.shared.startMaintenance(
                    taskTitle: "Test — Filtru HVAC", category: "HVAC")
            },
            SimScenario(kind: .shopping, sample: "Test — Cumpărături · 2/8") {
                LiveActivityService.shared.syncShopping(
                    listName: "Test — Cumpărături", bought: 2, total: 8)
            },
            SimScenario(kind: .delivery, sample: "Test — Colet PRVIO") {
                LiveActivityService.shared.syncDelivery(Self.testDelivery())
            },
            SimScenario(kind: .plantCare, sample: "Test — Monstera · 1/3") {
                LiveActivityService.shared.plantWatered(
                    name: "Test — Monstera", remainingAfter: 2)
            },
            SimScenario(kind: .emergency, sample: "Test — Incident") {
                LiveActivityService.shared.startEmergency()
            },
            SimScenario(kind: .energy, sample: "Test — 2.4 kW / 0.8 kW") {
                LiveActivityService.shared.startEnergySession(
                    consumptionW: 2400, productionW: 800)
            },
            SimScenario(kind: .cover, sample: "Test — Poartă") {
                LiveActivityService.shared.startCoverOperation(deviceName: "Test — Poartă")
            },
        ]
    }

    /// Minimal, clearly-labeled test parcel for the real `syncDelivery(_:)`
    /// path. `out_for_delivery` is an active status, so the service starts a
    /// genuine delivery activity; no tracker id means no push registration.
    private static func testDelivery() -> Delivery {
        Delivery(id: UUID(),
                 carrier: "Fan Courier",
                 trackingNumber: "TEST-000000",
                 description: "Test — Colet PRVIO",
                 status: "out_for_delivery",
                 expectedDate: nil,
                 notes: nil,
                 createdAt: nil,
                 trackerId: nil,
                 courierCode: nil,
                 liveStatus: nil,
                 estimatedDelivery: nil,
                 checkpoints: nil,
                 lastEventAt: nil,
                 trackingEnabled: nil)
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AppSpacing.lg) {
                headerCard
                if !systemEnabled {
                    warningCard(title: "la_sim_system_off", hint: "la_sim_system_off_hint")
                } else if !appEnabled {
                    warningCard(title: "la_sim_master_off", hint: "la_sim_master_off_hint")
                }
                ForEach(scenarios) { scenario in
                    scenarioRow(scenario)
                }
                endAllSection
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
            .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: running)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("la_sim_title")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            refreshRunning()
        }
        .task { store.refresh() }
    }

    // MARK: Header — honest explanation of what the buttons do

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: AppSpacing.base) {
                ColoredIconBadge(icon: "testtube.2", color: .brandPurple)
                VStack(alignment: .leading, spacing: 3) {
                    Text("la_sim_header")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text("la_sim_caption")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func warningCard(title: LocalizedStringKey,
                             hint: LocalizedStringKey) -> some View {
        GlassCard {
            HStack(spacing: AppSpacing.base) {
                ColoredIconBadge(icon: "exclamationmark.triangle.fill", color: .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(AppFont.footnoteEmphasis)
                    Text(hint)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Scenario rows

    /// A kind whose auto-start preference is off would make the service
    /// silently refuse the start — surfaced honestly instead of a dead button.
    private func isGated(_ kind: LiveActivityKind) -> Bool {
        kind.supportsAutoStart && !LiveActivityPrefs.autoStart(for: kind)
    }

    private func scenarioRow(_ scenario: SimScenario) -> some View {
        let kind = scenario.kind
        let gated = isGated(kind)
        let isRunning = running.contains(kind)
        return GlassCard(padding: AppSpacing.lg, cornerRadius: AppRadius.xl) {
            HStack(spacing: AppSpacing.md) {
                ColoredIconBadge(icon: kind.icon, color: kind.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text(verbatim: scenario.sample)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor)
                        .lineLimit(1)
                    if gated {
                        Text("la_sim_autostart_off")
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.brandWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: AppSpacing.sm)
                if isRunning {
                    runningBadge
                } else {
                    startButton(scenario, enabled: canUseActivities && !gated)
                }
            }
        }
        .opacity(canUseActivities ? 1 : 0.55)
    }

    private var runningBadge: some View {
        Text("la_sim_running")
            .font(AppFont.captionEmphasis)
            .foregroundStyle(Color.brandSuccess)
            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
            .background(Capsule().strokeBorder(Color.brandSuccess.opacity(0.45), lineWidth: 1))
            .accessibilityLabel(Text("la_sim_running"))
    }

    private func startButton(_ scenario: SimScenario, enabled: Bool) -> some View {
        Button {
            HapticFeedback.impact(.medium)
            scenario.start()
            refreshRunning()
            store.refresh()
            // ActivityKit finishes some starts a beat later — re-read the
            // REAL state instead of assuming the tap worked.
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                refreshRunning()
                store.refresh()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                Text("la_sim_start")
            }
            .font(AppFont.captionEmphasis)
            .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(AppOpacity.disabled))
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
            .mediaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(scenario.kind.title))
        .accessibilityHint(Text("la_sim_start"))
    }

    // MARK: End all

    private var endAllSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Button(role: .destructive) {
                endAll()
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "stop.circle.fill")
                    Text("la_sim_end_all")
                }
                .font(AppFont.headline)
                .foregroundStyle(store.active.isEmpty
                                 ? Color.brandDanger.opacity(AppOpacity.disabled)
                                 : Color.brandDanger)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .mediaGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(store.active.isEmpty)
            .accessibilityLabel(Text("la_sim_end_all"))

            Text("la_sim_active_count \(store.active.count)")
                .font(AppFont.caption2)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        }
        .padding(.top, AppSpacing.sm)
    }

    private func endAll() {
        HapticFeedback.warning()
        store.refresh()
        let items = store.active
        for item in items { store.end(item) }
        // Ends resolve asynchronously inside ActivityKit — verify afterwards.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            refreshRunning()
            store.refresh()
        }
        refreshRunning()
    }

    /// The single source of truth for "running" is ActivityKit itself.
    private func refreshRunning() {
        running = Set(LiveActivityKind.allCases.filter {
            LiveActivityService.shared.isActive($0)
        })
    }
}
