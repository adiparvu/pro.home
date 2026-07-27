import SwiftUI
import HomeKit

// MARK: - Scene surfaces (Smart Control R2)
//
// The ONE scene execution path and chip language shared by every scene
// surface — the dashboard's chip row, the space page's quick chips, and the
// hub's full list sheet. All of them bind to `HomeKitService.scenes` (the
// only provider that models scenes today; the IoT hub has none), so the
// surfaces can never drift apart on what a scene is or how it runs.
//
// Execution honesty (per surface, one `SceneRunner`):
// - Tap → the chip/row swaps its icon for a live spinner and disables
//   itself; the scene runs through the real `executeActionSet` bridge.
// - Success → success haptic, spinner ends. Failure → error haptic and an
//   alert carrying HomeKit's error VERBATIM — never a softened summary.
// - A long execute keeps the spinner for at most 10 s, then the honest
//   "încă se execută" note appears: HomeKit has no cancel, the command is
//   still running — the UI says exactly that instead of pretending it
//   finished or failed. Whenever the run eventually completes, the note
//   clears and the truthful outcome (haptic / alert) still lands.
// - No polling anywhere: one await per run, one watchdog sleep per run.

// MARK: - Runner

/// Per-surface scene execution state: which scenes are in flight, which
/// outlived the UI timeout (still running, honestly noted), and the last
/// failure for the surface's alert. Each surface owns one as `@State`, so
/// a dismissed sheet's in-flight state never haunts another surface.
@MainActor
@Observable
final class SceneRunner {
    /// The truthful failure of one run — scene name + HomeKit's verbatim
    /// error message, presented by the surface's alert.
    struct Failure: Identifiable {
        let id = UUID()
        let sceneName: String
        let message: String
    }

    /// Scenes whose execute is awaiting its outcome — the control stays
    /// disabled the whole time (HomeKit has no cancel; a re-tap would only
    /// double-execute).
    private(set) var runningIDs: Set<UUID> = []
    /// Scene names that outlived `uiTimeout` and are STILL executing —
    /// the spinner yields to the honest "încă se execută" note until the
    /// run resolves.
    private(set) var stillRunningNames: [UUID: String] = [:]
    var failure: Failure? = nil

    /// How long the spinner holds before the honest still-running note
    /// takes over. The command is NOT cancelled — HomeKit has no cancel.
    private static let uiTimeout: Duration = .seconds(10)

    /// Whether the control is mid-run (disabled state).
    func isRunning(_ scene: HomeKitScene) -> Bool {
        runningIDs.contains(scene.id)
    }

    /// Whether the live spinner shows — running AND not yet overdue.
    func showsSpinner(for scene: HomeKitScene) -> Bool {
        runningIDs.contains(scene.id) && stillRunningNames[scene.id] == nil
    }

    /// Executes a scene with the shared spinner/haptic/alert contract.
    /// Re-taps while in flight are ignored (the control is disabled too).
    func run(_ scene: HomeKitScene) {
        guard !runningIDs.contains(scene.id) else { return }
        runningIDs.insert(scene.id)
        Task { @MainActor in
            // The watchdog only ends the SPINNER (the note takes over);
            // the execute below keeps awaiting the real outcome.
            let watchdog = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.uiTimeout)
                guard let self, !Task.isCancelled,
                      self.runningIDs.contains(scene.id) else { return }
                self.stillRunningNames[scene.id] = scene.name
            }
            defer {
                watchdog.cancel()
                runningIDs.remove(scene.id)
                stillRunningNames[scene.id] = nil
            }
            do {
                try await HomeKitService.shared.executeScene(scene)
                HapticFeedback.success()
            } catch {
                HapticFeedback.error()
                failure = Failure(sceneName: scene.name,
                                  message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Failure alert (shared by all scene surfaces)

extension View {
    /// The honest scene-failure alert: the failing scene's name in the
    /// title, HomeKit's error message verbatim in the body.
    func sceneFailureAlert(_ runner: SceneRunner) -> some View {
        alert(
            Text("sh_scene_error_title \(runner.failure?.sceneName ?? "")"),
            isPresented: Binding(get: { runner.failure != nil },
                                 set: { if !$0 { runner.failure = nil } }),
            presenting: runner.failure
        ) { _ in
            Button(role: .cancel) {} label: { Text("OK") }
        } message: { failure in
            Text(verbatim: failure.message)
        }
    }
}

// MARK: - Scene chip

/// The scene capsule — `GlassFilterChip`'s exact metrics and material, with
/// the scene-type glyph leading and a live spinner replacing it while the
/// run is in flight. Never a selected state: executing is a moment, not a
/// filter.
struct SmartSceneChip: View {
    let scene: HomeKitScene
    let runner: SceneRunner

    private var isRunning: Bool { runner.isRunning(scene) }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            runner.run(scene)
        } label: {
            HStack(spacing: 5) {
                Group {
                    if runner.showsSpinner(for: scene) {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: scene.type.icon)
                            .font(AppFont.scaled(11, weight: .medium))
                    }
                }
                .frame(width: 14, height: 14)
                Text(verbatim: scene.name)
                    .font(AppFont.scaled(13, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 7)
            .glassFilterCapsule(selected: false)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: scene.name))
        .accessibilityValue(isRunning ? Text("sh_scene_running") : Text(verbatim: ""))
        .accessibilityHint(Text("sh_scene_run_hint"))
    }
}

// MARK: - Scene chip row (dashboard + space page)

/// One horizontal row of scene chips with the shared execution contract:
/// per-chip spinners, the surface's failure alert, and the honest
/// still-running notes beneath the row. Callers render it only when
/// `scenes` is non-empty — an empty row never exists.
struct SmartSceneChipRow: View {
    let scenes: [HomeKitScene]

    @State private var runner = SceneRunner()

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(scenes) { scene in
                        SmartSceneChip(scene: scene, runner: runner)
                    }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
            // The honest patience note: the spinner capped out, the command
            // is still running (HomeKit has no cancel) — one line per scene,
            // gone the moment the run resolves.
            ForEach(stillRunning, id: \.self) { name in
                Text("sh_scene_still_running \(name)")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
        .sceneFailureAlert(runner)
    }

    /// Stable order for the notes so two slow scenes don't swap lines.
    private var stillRunning: [String] {
        runner.stillRunningNames.values.sorted()
    }
}

// MARK: - Scene list sheet (the hub's "Scene" destination)

/// The hub's full scene list: every executable scene across the homes, the
/// type glyph leading, the home name as the subtle origin distinction when
/// more than one home exists. Tapping a row runs the scene with the shared
/// contract (spinner in the trailing slot, haptics, verbatim-error alert,
/// still-running note under the row).
struct SmartSceneListSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let homeKit = HomeKitService.shared

    @State private var runner = SceneRunner()
    @State private var showEditor = false
    @State private var editingScene: HomeKitScene?

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    topBar
                    content
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sceneFailureAlert(runner)
        .sheet(isPresented: $showEditor) { SceneEditorSheet() }
        .sheet(item: $editingScene) { SceneEditorSheet(editing: $0) }
    }

    @ViewBuilder private var content: some View {
        let scenes = homeKit.scenes
        if scenes.isEmpty {
            // Reachable only if the scenes vanished while the sheet was up
            // (a delegate update) — the same honest caption as the hub row.
            Text("hub_scenes_empty")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppSpacing.xxs)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let showsHomeName = Set(scenes.map { $0.home.uniqueIdentifier }).count > 1
            ForEach(scenes) { scene in
                sceneRow(scene, showsHomeName: showsHomeName)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Text("hub_scenes")
                .font(AppFont.scaled(26, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            // Creation exists only when a home is actually connected — the
            // editor would otherwise open onto an honest but useless void.
            if !homeKit.homes.isEmpty {
                Button {
                    HapticFeedback.impact(.light)
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .accessibilityLabel(Text("sh_scene_new"))
            }
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

    private func sceneRow(_ scene: HomeKitScene, showsHomeName: Bool) -> some View {
        let isRunning = runner.isRunning(scene)
        let showsSpinner = runner.showsSpinner(for: scene)
        let stillRunning = runner.stillRunningNames[scene.id] != nil
        return Button {
            HapticFeedback.impact(.light)
            runner.run(scene)
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: scene.type.icon)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: scene.name)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if showsHomeName {
                        Text(verbatim: scene.homeName)
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if stillRunning {
                        Text("sh_scene_still_running_short")
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: AppSpacing.sm)
                if showsSpinner {
                    ProgressView()
                } else {
                    Image(systemName: "play.circle")
                        .font(AppFont.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(SmartCardPressStyle())
        .liquidGlass(cornerRadius: AppRadius.lg)
        .disabled(isRunning)
        .contextMenu {
            Button {
                editingScene = scene
            } label: { Label("sh_scene_edit", systemImage: "pencil") }
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { try? await homeKit.deleteScene(scene) }
            } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRunning ? Text("sh_scene_running") : Text(verbatim: ""))
        .accessibilityHint(Text("sh_scene_run_hint"))
    }
}
