import SwiftUI
import HomeKit

// Links a property element to a HomeKit accessory and lets the user toggle it.
// Degrades gracefully when HomeKit is unavailable or there are no accessories.

struct ElementSmartControlSection: View {
    let elementId: UUID

    @Environment(PropertyElementService.self) private var elementService
    var homeKit = HomeKitService.shared
    @State private var showPicker = false

    private var element: PropertyElement? { elementService.elements.first { $0.id == elementId } }

    private var linkedAccessory: HMAccessory? {
        guard let id = element?.homekitAccessoryId else { return nil }
        return homeKit.allAccessories().first { $0.uniqueIdentifier.uuidString == id }
    }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Smart control (HomeKit)", systemImage: "homekit")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                if let acc = linkedAccessory {
                    HStack(spacing: 12) {
                        Image(systemName: homeKit.isOn(acc) ? "power.circle.fill" : "power.circle")
                            .font(AppFont.scaled(26))
                            .foregroundStyle(homeKit.isOn(acc) ? Color.green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(acc.name).font(AppFont.subheadline)
                            Text(homeKit.isOn(acc) ? String(localized: "On") : String(localized: "Off"))
                                .font(AppFont.scaled(12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { try? await homeKit.toggle(acc) }
                            HapticFeedback.impact(.medium)
                        } label: {
                            Text("Toggle").font(AppFont.footnoteEmphasis)
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Button(role: .destructive) {
                        Task { await elementService.updateHomeKit(elementId: elementId, accessoryId: nil) }
                    } label: {
                        Label("Unlink", systemImage: "link.badge.plus").font(.caption)
                    }
                } else if element?.homekitAccessoryId != nil {
                    Text("Linked accessory isn't reachable right now.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        Task { await elementService.updateHomeKit(elementId: elementId, accessoryId: nil) }
                    } label: { Label("Unlink", systemImage: "xmark.circle").font(.caption) }
                } else {
                    Button {
                        homeKit.requestAccess()
                        showPicker = true
                    } label: {
                        Label("Link HomeKit accessory", systemImage: "homekit")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { homeKit.requestAccess() }
        .sheet(isPresented: $showPicker) { picker }
    }

    private var picker: some View {
        NavigationStack {
            ZStack {
                Color.clear
                let accs = homeKit.allAccessories()
                if accs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "homekit").font(AppFont.scaled(40)).foregroundStyle(.secondary)
                        Text("No HomeKit accessories found").font(.headline)
                        Text("Add accessories in Apple's Home app, then try again.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    List(accs, id: \.uniqueIdentifier) { acc in
                        Button {
                            Task {
                                await elementService.updateHomeKit(elementId: elementId, accessoryId: acc.uniqueIdentifier.uuidString)
                                showPicker = false
                            }
                            HapticFeedback.success()
                        } label: {
                            HStack {
                                Image(systemName: "lightbulb.fill").foregroundStyle(Color.accentColor)
                                Text(acc.name)
                                Spacer()
                                if element?.homekitAccessoryId == acc.uniqueIdentifier.uuidString {
                                    Image(systemName: "checkmark").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Choose accessory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPicker = false } } }
        }
        .sheetGround()
    }
}
