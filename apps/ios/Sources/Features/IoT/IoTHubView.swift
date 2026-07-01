import SwiftUI

// MARK: - IoT Hub (Controllers / Sensors / Automations)

struct IoTHubView: View {
    @StateObject private var service = IoTService.shared
    @State private var tab: HubTab = .controllers
    @State private var showAddController = false
    @State private var showAddSensor = false
    @State private var showAddAutomation = false
    @State private var selectedDevice: IoTDevice?
    @State private var selectedSensor: IoTSensor?

    enum HubTab: String, CaseIterable {
        case controllers = "Controllers"
        case sensors     = "Sensors"
        case automations = "Automations"
        var icon: String {
            switch self {
            case .controllers: return "cpu.fill"
            case .sensors:     return "sensor.tag.radiowaves.forward.fill"
            case .automations: return "bolt.badge.automatic.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(titleKey: "Local Controllers", subtitleKey: "IOT HUB")

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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
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
                            .font(.system(size: 17, weight: .semibold))
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
                            .font(.system(size: 14, weight: tab == t ? .semibold : .regular))
                        Text(t.rawValue)
                            .font(.system(size: 11, weight: tab == t ? .semibold : .regular))
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
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    Spacer(minLength: 100)
                }
            }
        }
    }

    private func deviceCard(_ device: IoTDevice) -> some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(device.type.color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: device.type.icon)
                        .font(.system(size: 20, weight: .semibold))
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
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    HStack(spacing: 4) {
                        Image(systemName: "sensor.tag.radiowaves.forward.fill")
                            .font(.system(size: 9))
                        Text("\(service.sensorsForDevice(device).count) sensors")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.primary.opacity(0.4))
                }

                Spacer()

                Button {
                    selectedDevice = device
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
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
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(service.sensors) { sensor in
                            sensorTile(sensor)
                                .onTapGesture { selectedSensor = sensor }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    Spacer(minLength: 100)
                }
            }
        }
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
                            .font(.system(size: 12))
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
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    } else if let updated = sensor.lastUpdated {
                        Text(relativeTime(updated))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                }
            }
        }
    }

    // MARK: - Automations tab

    private var automationsTab: some View {
        Group {
            if service.automations.isEmpty {
                iotEmptyState(
                    icon: "bolt.badge.automatic.fill",
                    title: "No automations yet",
                    body: "Create IF/THEN rules: when a sensor exceeds a threshold, send a notification, create a task or call a webhook."
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(service.automations) { auto in
                            automationRow(auto)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    Spacer(minLength: 100)
                }
            }
        }
    }

    private func automationRow(_ auto: IoTAutomation) -> some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: auto.action.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(auto.name)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text("IF \(auto.conditionDescription)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Text("THEN \(auto.action.rawValue)")
                        .font(.system(size: 11))
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

    private func iotEmptyState(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button { addAction() } label: {
                Label("Add", systemImage: "plus")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 11)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
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
