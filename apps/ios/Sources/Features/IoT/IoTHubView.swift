import SwiftUI
import UIKit

// MARK: - IoT Hub (Controllers / Sensors / Automations)

struct IoTHubView: View {
    @State private var service = IoTService.shared
    @State private var tab: HubTab = .controllers
    @State private var showAddController = false
    @State private var showAddSensor = false
    @State private var showAddAutomation = false
    @State private var selectedDevice: IoTDevice?
    @State private var selectedSensor: IoTSensor?
    @State private var energyPinned = false
    @State private var webhookCopied = false

    enum HubTab: CaseIterable {
        case controllers, sensors, automations
        var label: LocalizedStringKey {
            switch self {
            case .controllers: return "iot_tab_controllers"
            case .sensors:     return "iot_tab_sensors"
            case .automations: return "iot_tab_automations"
            }
        }
        var icon: String {
            switch self {
            case .controllers: return "cpu.fill"
            case .sensors:     return "sensor.tag.radiowaves.forward.fill"
            case .automations: return "bolt.badge.automatic.fill"
            }
        }
        /// The deeply detailed "how does this work?" walkthrough per tab.
        var guide: GuideTopic {
            switch self {
            case .controllers: return IoTGuides.controllers
            case .sensors:     return IoTGuides.sensors
            case .automations: return IoTGuides.automations
            }
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {

                // Tab bar
                hubTabBar

                // Content
                ZStack {
                    if tab == .controllers { controllersTab }
                    if tab == .sensors     { sensorsTab }
                    if tab == .automations { automationsTab }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Local Controllers")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    GuideInfoButton(topic: tab.guide)
                    if service.isPolling {
                        ProgressView().tint(Color.accentColor).scaleEffect(0.85)
                    } else {
                        Button { Task { await service.pollAllDevices() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(AppFont.body)
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Refresh devices")
                    }
                    Button { addAction() } label: {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Add item")
                }
            }
        }
        .onAppear { service.startPolling() }
        .onDisappear { service.stopPolling() }
        .sheet(isPresented: $showAddController) {
            AddControllerSheet { device in
                service.addDevice(device)
            }
        }
        .sheet(isPresented: $showAddSensor) {
            AddSensorSheet(devices: service.devices) { sensor in
                service.addSensor(sensor)
            }
        }
        .sheet(isPresented: $showAddAutomation) {
            AddIoTAutomationSheet(sensors: service.sensors) { automation in
                service.addAutomation(automation)
            }
        }
        .sheet(item: $selectedDevice) { device in
            DeviceDetailSheet(device: device, service: service)
        }
        .sheet(item: $selectedSensor) { sensor in
            SensorDetailSheet(sensor: sensor, service: service)
        }
    }

    private var hubTabBar: some View {
        HStack(spacing: 0) {
            ForEach(HubTab.allCases, id: \.self) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { tab = t }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon)
                            .font(AppFont.scaled(14, weight: tab == t ? .semibold : .regular))
                        Text(t.label)
                            .font(AppFont.scaled(11, weight: tab == t ? .semibold : .regular))
                    }
                    .foregroundStyle(tab == t ? Color.accentColor : Color.primary.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.sm)
    }

    private func addAction() {
        switch tab {
        case .controllers: showAddController = true
        case .sensors:     showAddSensor = true
        case .automations: showAddAutomation = true
        }
    }

    // MARK: - Controllers tab

    private var controllersTab: some View {
        Group {
            if service.devices.isEmpty {
                iotEmptyState(
                    icon: "cpu.fill",
                    title: "No controllers yet",
                    body: "Add an ESP32, Raspberry Pi or RS485 gateway to start reading sensor data."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(service.devices) { device in
                            deviceCard(device)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.xxs)
                    Spacer(minLength: 100)
                }
            }
        }
    }

    private func deviceCard(_ device: IoTDevice) -> some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(device.type.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: device.type.icon)
                        .font(AppFont.scaled(20, weight: .semibold))
                        .foregroundStyle(device.type.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Circle()
                            .fill(device.isConnected ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                    }
                    Text("\(device.host):\(device.port) · \(device.connectionProtocol.rawValue)")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    HStack(spacing: 4) {
                        Image(systemName: "sensor.tag.radiowaves.forward.fill")
                            .font(AppFont.scaled(9))
                        Text("\(service.sensorsForDevice(device).count) sensors")
                            .font(AppFont.scaled(11))
                    }
                    .foregroundStyle(Color.primary.opacity(0.4))
                }

                Spacer()

                Button {
                    selectedDevice = device
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(AppFont.scaled(22))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show device options")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                service.removeDevice(device)
            } label: { Label("Delete", systemImage: "trash") }
        }
        .onTapGesture { tab = .sensors }
    }

    // MARK: - Sensors tab

    private var sensorsTab: some View {
        Group {
            if service.sensors.isEmpty {
                iotEmptyState(
                    icon: "sensor.tag.radiowaves.forward.fill",
                    title: "No sensors yet",
                    body: "Sensors are auto-discovered when a controller polls. You can also add them manually."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    if service.currentConsumptionW != nil || service.currentProductionW != nil {
                        energyCard
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.top, AppSpacing.xxs)
                            .padding(.bottom, AppSpacing.md)
                    }
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(service.sensors) { sensor in
                            sensorTile(sensor)
                                .onTapGesture { selectedSensor = sensor }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.xxs)
                    Spacer(minLength: 100)
                }
            }
        }
    }

    // MARK: - Energy card (live wattage + Dynamic Island pin)

    private static func watts(_ w: Double?) -> String? {
        guard let w else { return nil }
        return w >= 1000 ? String(format: "%.1f kW", w / 1000)
                         : String(format: "%.0f W", w)
    }

    private var energyCard: some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.brandGold.opacity(AppOpacity.tintedFill))
                        .frame(width: 44, height: 44)
                    Image(systemName: "bolt.fill")
                        .font(AppFont.title3)
                        .foregroundStyle(Color.brandGold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let consumption = Self.watts(service.currentConsumptionW) {
                            Text(verbatim: consumption)
                                .font(AppFont.subheadline)
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                        if let production = Self.watts(service.currentProductionW) {
                            Label {
                                Text(verbatim: production).font(AppFont.captionStrong)
                            } icon: {
                                Image(systemName: "sun.max.fill")
                            }
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.brandSuccess)
                            .labelStyle(.titleAndIcon)
                        }
                    }
                    Text("iot_energy_pin_subtitle")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    if energyPinned {
                        LiveActivityService.shared.endEnergySession()
                        energyPinned = false
                        HapticFeedback.impact(.light)
                    } else {
                        LiveActivityService.shared.startEnergySession(
                            consumptionW: service.currentConsumptionW,
                            productionW: service.currentProductionW)
                        energyPinned = LiveActivityService.shared.isActive(.energy)
                        if energyPinned { HapticFeedback.impact(.medium) }
                    }
                } label: {
                    Image(systemName: energyPinned ? "pin.circle.fill" : "pin.circle")
                        .font(AppFont.scaled(26))
                        .foregroundStyle(energyPinned ? Color.brandGold : Color.primary.opacity(0.3))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(energyPinned ? "emergency_pin_on" : "emergency_pin_off"))
            }
        }
        .onAppear { energyPinned = LiveActivityService.shared.isActive(.energy) }
    }

    private func sensorTile(_ sensor: IoTSensor) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(sensor.type.color.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: sensor.type.icon)
                            .font(AppFont.subheadline)
                            .foregroundStyle(sensor.type.color)
                    }
                    Spacer()
                    if sensor.isAlerting {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.orange)
                    }
                }

                Text(sensor.displayValue)
                    .font(AppFont.title2)
                    .foregroundStyle(sensor.isAlerting ? .orange : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sensor.name)
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !sensor.linkedZoneName.isEmpty {
                        Text(sensor.linkedZoneName)
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    } else if let updated = sensor.lastUpdated {
                        Text(relativeTime(updated))
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                }
            }
        }
    }

    // MARK: - Automations tab

    private var automationsTab: some View {
        ScrollView(showsIndicators: false) {
            webhookCard
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xxs)
                .padding(.bottom, AppSpacing.md)
            if service.automations.isEmpty {
                EmptyStateView(
                    icon: "bolt.badge.automatic.fill",
                    title: "No automations yet",
                    message: "Create IF/THEN rules: when a sensor exceeds a threshold, send a notification, create a task or call a webhook.",
                    actionLabel: "Add",
                    action: { addAction() }
                )
                .padding(.top, AppSpacing.xxl)
            } else {
                VStack(spacing: 10) {
                    ForEach(service.automations) { auto in
                        automationRow(auto)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
            }
            Spacer(minLength: 100)
        }
    }

    // MARK: - Locked-phone webhook card
    //
    // The controller (or a "Phone Alert" automation) POSTs alarms to this
    // per-account URL; the iot-event edge function pushes them onto the
    // Dynamic Island and Lock Screen even with PRVIO closed.

    private var webhookCard: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "iphone.radiowaves.left.and.right",
                                     color: Color.brandPurple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iot_webhook_title")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        Text("iot_webhook_subtitle")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Button {
                    guard let url = service.webhookURL else { return }
                    UIPasteboard.general.string = url.absoluteString
                    webhookCopied = true
                    HapticFeedback.success()
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        webhookCopied = false
                    }
                } label: {
                    Label(webhookCopied ? "iot_webhook_copied" : "iot_webhook_copy",
                          systemImage: webhookCopied ? "checkmark" : "doc.on.doc")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(AppOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(service.webhookURL == nil)
                .opacity(service.webhookURL == nil ? 0.5 : 1)
            }
        }
        .task { await service.ensureWebhook() }
    }

    private func automationRow(_ auto: IoTAutomation) -> some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: auto.action.icon)
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(auto.name)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text("IF \(auto.conditionDescription)")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Text("THEN \(auto.action.rawValue)")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { auto.isEnabled },
                    set: { _ in service.toggleAutomation(auto) }
                ))
                .labelsHidden()
                .tint(Color.accentColor)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                service.removeAutomation(auto)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Empty state

    private func iotEmptyState(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        VStack {
            Spacer()
            EmptyStateView(
                icon: icon,
                title: title,
                message: body,
                actionLabel: "Add",
                action: { addAction() }
            )
            Spacer()
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        return "\(Int(diff/3600))h ago"
    }
}
