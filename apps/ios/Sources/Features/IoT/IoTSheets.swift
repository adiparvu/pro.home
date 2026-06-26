import SwiftUI
import Network

// MARK: - Add Controller Sheet

struct AddControllerSheet: View {
    var onAdd: (IoTDevice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: IoTDevice.DeviceType = .esp32
    @State private var host = ""
    @State private var port = "80"
    @State private var proto: IoTDevice.ConnectionProtocol = .http
    @State private var apiPath = "/sensors"
    @State private var unitId = "1"
    @State private var testing = false
    @State private var testResult: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    TextField("Name (e.g. Living Room ESP32)", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(IoTDevice.DeviceType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    .onChange(of: type) { _, t in
                        port = String(t.defaultPort)
                        proto = t.defaultProtocol
                    }
                }

                Section("Network") {
                    TextField("Host / IP Address", text: $host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Picker("Protocol", selection: $proto) {
                        ForEach(IoTDevice.ConnectionProtocol.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    Text(proto.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if proto == .http {
                    Section("HTTP Settings") {
                        TextField("API Path", text: $apiPath)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                if proto == .modbusTCP {
                    Section("Modbus Settings") {
                        HStack {
                            Text("Unit ID")
                            Spacer()
                            TextField("1", text: $unitId)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            if testing {
                                ProgressView().scaleEffect(0.8)
                            } else if let r = testResult {
                                Image(systemName: r ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(r ? .green : .red)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(host.isEmpty || testing)
                }
            }
            .navigationTitle("Add Controller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addDevice() }
                        .disabled(name.isEmpty || host.isEmpty)
                }
            }
        }
    }

    private func addDevice() {
        let device = IoTDevice(
            name: name, type: type,
            host: host, port: Int(port) ?? type.defaultPort,
            connectionProtocol: proto,
            apiPath: apiPath,
            unitId: Int(unitId) ?? 1
        )
        onAdd(device)
        dismiss()
    }

    private func runTest() async {
        testing = true; testResult = nil
        let device = IoTDevice(
            name: name, type: type,
            host: host, port: Int(port) ?? type.defaultPort,
            connectionProtocol: proto,
            apiPath: apiPath,
            unitId: Int(unitId) ?? 1
        )
        testResult = await IoTService.shared.testConnection(device)
        testing = false
    }
}

// MARK: - Add Sensor Sheet

struct AddSensorSheet: View {
    let devices: [IoTDevice]
    var onAdd: (IoTSensor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedDeviceId: UUID?
    @State private var sensorType: IoTSensor.SensorType = .temperature
    @State private var unit = "°C"
    @State private var remoteId = ""
    @State private var linkedZone = ""
    @State private var alertMinStr = ""
    @State private var alertMaxStr = ""
    @State private var modbusAddrStr = ""
    @State private var modbusScaleStr = "1.0"

    private var selectedDevice: IoTDevice? {
        devices.first { $0.id == selectedDeviceId }
    }
    private var isModbus: Bool { selectedDevice?.connectionProtocol == .modbusTCP }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sensor Info") {
                    TextField("Name (e.g. Temperature Sensor 1)", text: $name)
                    Picker("Type", selection: $sensorType) {
                        ForEach(IoTSensor.SensorType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.icon).tag(t)
                        }
                    }
                    .onChange(of: sensorType) { _, t in
                        if unit.isEmpty || unit == sensorType.defaultUnit {
                            unit = t.defaultUnit
                        }
                    }
                    HStack {
                        Text("Unit")
                        Spacer()
                        TextField("e.g. °C", text: $unit)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                    }
                }

                Section("Controller") {
                    Picker("Device", selection: $selectedDeviceId) {
                        Text("None").tag(nil as UUID?)
                        ForEach(devices) { d in
                            Text(d.name).tag(d.id as UUID?)
                        }
                    }
                    if !isModbus {
                        TextField("Remote ID (from JSON response)", text: $remoteId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                if isModbus {
                    Section("Modbus") {
                        HStack {
                            Text("Register Address")
                            Spacer()
                            TextField("0", text: $modbusAddrStr)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(width: 80)
                        }
                        HStack {
                            Text("Scale Factor")
                            Spacer()
                            TextField("1.0", text: $modbusScaleStr)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(width: 80)
                        }
                    }
                }

                Section("Alerts (optional)") {
                    HStack {
                        Text("Alert below")
                        Spacer()
                        TextField("Min", text: $alertMinStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("Alert above")
                        Spacer()
                        TextField("Max", text: $alertMaxStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 80)
                    }
                }

                Section("Zone (optional)") {
                    TextField("Linked zone name", text: $linkedZone)
                }
            }
            .navigationTitle("Add Sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSensor() }
                        .disabled(name.isEmpty || selectedDeviceId == nil)
                }
            }
        }
    }

    private func addSensor() {
        guard let deviceId = selectedDeviceId else { return }
        var sensor = IoTSensor(
            deviceId: deviceId,
            remoteId: remoteId.isEmpty ? name.lowercased().replacingOccurrences(of: " ", with: "_") : remoteId,
            name: name,
            type: sensorType,
            unit: unit.isEmpty ? sensorType.defaultUnit : unit,
            value: nil, lastUpdated: nil
        )
        sensor.linkedZoneName = linkedZone
        sensor.alertMin = Double(alertMinStr)
        sensor.alertMax = Double(alertMaxStr)
        if isModbus {
            sensor.modbusAddress = Int(modbusAddrStr)
            sensor.modbusScale = Double(modbusScaleStr) ?? 1.0
        }
        onAdd(sensor)
        dismiss()
    }
}

// MARK: - Device Detail Sheet

struct DeviceDetailSheet: View {
    let device: IoTDevice
    @ObservedObject var service: IoTService
    @Environment(\.dismiss) private var dismiss
    @State private var testing = false
    @State private var testResult: Bool?
    @State private var showDeleteConfirm = false

    private var sensors: [IoTSensor] { service.sensorsForDevice(device) }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Connection") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(device.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(device.isConnected ? "Connected" : "Offline")
                                .foregroundStyle(device.isConnected ? .green : .red)
                        }
                    }
                    if let seen = device.lastSeen {
                        LabeledContent("Last Seen", value: seen, format: .relative(presentation: .named))
                    }
                    LabeledContent("Type", value: device.type.label)
                    LabeledContent("Protocol", value: device.connectionProtocol.rawValue)
                    LabeledContent("Host", value: "\(device.host):\(device.port)")
                    if device.connectionProtocol == .http {
                        LabeledContent("API Path", value: device.apiPath)
                    } else {
                        LabeledContent("Unit ID", value: "\(device.unitId)")
                    }
                }

                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            if testing {
                                ProgressView().scaleEffect(0.8)
                            } else if let r = testResult {
                                Image(systemName: r ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(r ? .green : .red)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(testing)
                    Button {
                        Task { await service.pollDevice(device) }
                    } label: {
                        Label("Poll Now", systemImage: "arrow.clockwise")
                    }
                }

                Section("Sensors (\(sensors.count))") {
                    if sensors.isEmpty {
                        Text("No sensors yet — poll the device to auto-discover.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sensors) { sensor in
                            HStack(spacing: 12) {
                                Image(systemName: sensor.type.icon)
                                    .foregroundStyle(sensor.type.color)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sensor.name).font(.subheadline.weight(.medium))
                                    Text(sensor.displayValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Remove Controller", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(device.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Remove \(device.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove Controller & Sensors", role: .destructive) {
                    service.removeDevice(device)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will also remove all \(sensors.count) sensors linked to this controller.")
            }
        }
    }

    private func runTest() async {
        testing = true; testResult = nil
        testResult = await service.testConnection(device)
        testing = false
    }
}

// MARK: - Sensor Detail Sheet

struct SensorDetailSheet: View {
    let sensor: IoTSensor
    @ObservedObject var service: IoTService
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    private var device: IoTDevice? { service.devices.first { $0.id == sensor.deviceId } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        ZStack {
                            Circle()
                                .fill(sensor.type.color.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Image(systemName: sensor.type.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(sensor.type.color)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sensor.displayValue)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(sensor.isAlerting ? .orange : .primary)
                            if let updated = sensor.lastUpdated {
                                Text(updated, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 4)
                }

                Section("Info") {
                    LabeledContent("Type", value: sensor.type.label)
                    LabeledContent("Unit", value: sensor.unit.isEmpty ? "—" : sensor.unit)
                    if let dev = device {
                        LabeledContent("Controller", value: dev.name)
                    }
                    if !sensor.linkedZoneName.isEmpty {
                        LabeledContent("Zone", value: sensor.linkedZoneName)
                    }
                    if let addr = sensor.modbusAddress {
                        LabeledContent("Modbus Address", value: "\(addr)")
                        LabeledContent("Scale Factor", value: String(format: "%.4g", sensor.modbusScale))
                    }
                }

                Section("Alerts") {
                    if let min = sensor.alertMin {
                        LabeledContent("Alert Below", value: String(format: "%.2g \(sensor.unit)", min))
                    } else {
                        LabeledContent("Alert Below", value: "Not set")
                    }
                    if let max = sensor.alertMax {
                        LabeledContent("Alert Above", value: String(format: "%.2g \(sensor.unit)", max))
                    } else {
                        LabeledContent("Alert Above", value: "Not set")
                    }
                    if sensor.isAlerting {
                        Label("Currently alerting", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Remove Sensor", systemImage: "trash")
                    }
                }
            }
            .navigationTitle(sensor.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Remove \(sensor.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove Sensor", role: .destructive) {
                    service.removeSensor(sensor)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

// MARK: - Add IoT Automation Sheet

struct AddIoTAutomationSheet: View {
    let sensors: [IoTSensor]
    var onAdd: (IoTAutomation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedSensorId: UUID?
    @State private var condition: IoTAutomation.TriggerCondition = .above
    @State private var triggerValueStr = "0"
    @State private var action: IoTAutomation.AutomationAction = .sendNotification
    @State private var payload = ""

    private var selectedSensor: IoTSensor? { sensors.first { $0.id == selectedSensorId } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Automation name", text: $name)
                }

                Section("IF — Trigger") {
                    Picker("Sensor", selection: $selectedSensorId) {
                        Text("Select sensor").tag(nil as UUID?)
                        ForEach(sensors) { s in
                            Label(s.name, systemImage: s.type.icon).tag(s.id as UUID?)
                        }
                    }
                    Picker("Condition", selection: $condition) {
                        ForEach(IoTAutomation.TriggerCondition.allCases, id: \.self) { c in
                            Text(conditionLabel(c)).tag(c)
                        }
                    }
                    HStack {
                        Text("Value\(selectedSensor.map { " (\($0.unit))" } ?? "")")
                        Spacer()
                        TextField("0", text: $triggerValueStr)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("THEN — Action") {
                    Picker("Action", selection: $action) {
                        ForEach(IoTAutomation.AutomationAction.allCases, id: \.self) { a in
                            Label(a.rawValue, systemImage: a.icon).tag(a)
                        }
                    }

                    switch action {
                    case .sendNotification:
                        TextField("Custom message (optional)", text: $payload)
                    case .callWebhook:
                        TextField("Webhook URL", text: $payload)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    case .createTask:
                        TextField("Task title (optional)", text: $payload)
                    }
                }

                if let s = selectedSensor {
                    Section("Preview") {
                        Text("IF \(s.name) \(condition.rawValue) \(triggerValueStr) \(s.unit)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("THEN \(action.rawValue)")
                            .font(.footnote)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .navigationTitle("New Automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addAutomation() }
                        .disabled(name.isEmpty || selectedSensorId == nil)
                }
            }
        }
    }

    private func addAutomation() {
        guard let sid = selectedSensorId,
              let sensor = selectedSensor else { return }
        let auto = IoTAutomation(
            name: name,
            isEnabled: true,
            triggerSensorId: sid,
            triggerSensorName: sensor.name,
            condition: condition,
            triggerValue: Double(triggerValueStr) ?? 0,
            action: action,
            actionPayload: payload
        )
        onAdd(auto)
        dismiss()
    }

    private func conditionLabel(_ c: IoTAutomation.TriggerCondition) -> String {
        switch c {
        case .above:  return "Is above (>)"
        case .below:  return "Is below (<)"
        case .equals: return "Equals (=)"
        }
    }
}
