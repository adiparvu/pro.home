import SwiftUI
import HomeKit

// MARK: - Scene editor (Smart Home S4 — creation & editing)
//
// Scenes were execute-only; this closes the loop. A scene here is a name
// plus one power command per picked device — the one capability every
// controllable accessory shares, written as a real HMActionSet (the Home
// app sees and runs the exact same scene). Editing rewrites the action set
// (remove-then-add — HomeKit has no in-place update); errors surface
// verbatim through FormScaffold's error slot.

struct SceneEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let homeKit = HomeKitService.shared

    var editing: HomeKitScene?

    @State private var name = ""
    @State private var homeID: UUID?
    /// accessory id → the power state the scene commands. Absent = excluded.
    @State private var picks: [UUID: Bool] = [:]
    @State private var isSaving = false
    @State private var error: String?
    @State private var hydrated = false

    private var home: HMHome? {
        if let editing { return editing.home }
        return homeKit.homes.first { $0.uniqueIdentifier == homeID } ?? homeKit.homes.first
    }

    private var candidates: [HMAccessory] {
        home.map { homeKit.sceneCandidates(in: $0) } ?? []
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !picks.isEmpty
    }

    var body: some View {
        FormScaffold(title: editing == nil ? "sh_scene_new" : "sh_scene_edit",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: "sparkles", tint: .accentColor) {
                    TextField("sh_scene_name_ph", text: $name).font(AppFont.body)
                }
                // The home picker exists only for creation across several
                // homes — an existing scene can never move home.
                if editing == nil && homeKit.homes.count > 1 {
                    FormDivider()
                    FormRow(icon: "house.fill", tint: .accentColor) {
                        Picker("sh_scene_home", selection: $homeID) {
                            ForEach(homeKit.homes, id: \.uniqueIdentifier) { h in
                                Text(verbatim: h.name).tag(UUID?.some(h.uniqueIdentifier))
                            }
                        }
                        .font(AppFont.body)
                    }
                }
            }

            FormGroup(title: "sh_scene_devices") {
                if candidates.isEmpty {
                    Text("sh_scene_no_devices")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .padding(AppSpacing.md)
                } else {
                    ForEach(candidates, id: \.uniqueIdentifier) { accessory in
                        deviceRow(accessory)
                        if accessory.uniqueIdentifier != candidates.last?.uniqueIdentifier {
                            FormDivider()
                        }
                    }
                }
            }
        }
        .onAppear(perform: hydrate)
        .onChange(of: homeID) { _, _ in
            // A different home — old picks would reference foreign devices.
            if editing == nil { picks = [:] }
        }
    }

    /// One row per controllable device: tap the circle to include it, the
    /// trailing pill picks what the scene commands (on/off).
    private func deviceRow(_ accessory: HMAccessory) -> some View {
        let id = accessory.uniqueIdentifier
        let included = picks[id] != nil
        return HStack(spacing: AppSpacing.md) {
            Button {
                HapticFeedback.selection()
                if included {
                    picks.removeValue(forKey: id)
                } else {
                    picks[id] = true
                }
            } label: {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20))
                    .foregroundStyle(included ? Color.accentColor : Color.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: accessory.name))
            .accessibilityValue(included ? Text("sh_scene_included") : Text(verbatim: ""))

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: accessory.name)
                    .font(AppFont.scaled(14, weight: .medium))
                    .foregroundStyle(included ? .primary : Color.secondaryTextColor)
                    .lineLimit(1)
                if let room = accessory.room?.name, !room.isEmpty {
                    Text(verbatim: room)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            Spacer()
            if included {
                SmartPillToggle(isOn: Binding(
                    get: { picks[id] ?? true },
                    set: { picks[id] = $0 }
                ), accessibilityLabel: Text(verbatim: accessory.name))
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true
        if let editing {
            name = editing.name
            picks = homeKit.powerPicks(of: editing)
        } else {
            homeID = homeKit.homes.first?.uniqueIdentifier
        }
    }

    private func save() {
        guard let home else { return }
        let selection = candidates.compactMap { accessory -> HomeKitService.SceneDevicePick? in
            picks[accessory.uniqueIdentifier].map {
                HomeKitService.SceneDevicePick(accessory: accessory, on: $0)
            }
        }
        guard !selection.isEmpty else { return }
        isSaving = true
        Task {
            do {
                if let editing {
                    try await homeKit.updateScene(editing,
                                                  name: name.trimmingCharacters(in: .whitespaces),
                                                  picks: selection)
                } else {
                    try await homeKit.addScene(named: name.trimmingCharacters(in: .whitespaces),
                                               in: home, picks: selection)
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }
}
