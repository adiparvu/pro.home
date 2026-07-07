import Foundation
import Observation
import Network
import UserNotifications

@MainActor
@Observable
final class IoTService {
    static let shared = IoTService()

    var devices: [IoTDevice] = []
    var sensors: [IoTSensor] = []
    var automations: [IoTAutomation] = []
    var isPolling = false

    private let devicesKey     = "prvio.iot.devices"
    private let sensorsKey     = "prvio.iot.sensors"
    private let automationsKey = "prvio.iot.automations"
    private var pollTimer: Timer?

    private init() { load() }

    // MARK: - Persistence

    func load() {
        if let d = UserDefaults.standard.data(forKey: devicesKey),
           let v = try? JSONDecoder().decode([IoTDevice].self, from: d) { devices = v }
        if let d = UserDefaults.standard.data(forKey: sensorsKey),
           let v = try? JSONDecoder().decode([IoTSensor].self, from: d) { sensors = v }
        if let d = UserDefaults.standard.data(forKey: automationsKey),
           let v = try? JSONDecoder().decode([IoTAutomation].self, from: d) { automations = v }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(devices)     { UserDefaults.standard.set(d, forKey: devicesKey) }
        if let d = try? JSONEncoder().encode(sensors)     { UserDefaults.standard.set(d, forKey: sensorsKey) }
        if let d = try? JSONEncoder().encode(automations) { UserDefaults.standard.set(d, forKey: automationsKey) }
    }

    // MARK: - Devices CRUD

    func addDevice(_ device: IoTDevice) {
        devices.append(device)
        persist()
        Task { await pollDevice(device) }
    }

    func removeDevice(_ device: IoTDevice) {
        devices.removeAll { $0.id == device.id }
        sensors.removeAll { $0.deviceId == device.id }
        persist()
    }

    func sensorsForDevice(_ device: IoTDevice) -> [IoTSensor] {
        sensors.filter { $0.deviceId == device.id }
    }

    // MARK: - Sensors CRUD

    func addSensor(_ sensor: IoTSensor) { sensors.append(sensor); persist() }

    func updateSensor(_ sensor: IoTSensor) {
        if let idx = sensors.firstIndex(where: { $0.id == sensor.id }) {
            sensors[idx] = sensor; persist()
        }
    }

    func removeSensor(_ sensor: IoTSensor) {
        sensors.removeAll { $0.id == sensor.id }; persist()
    }

    // MARK: - Polling

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.pollAllDevices() }
        }
        Task { await pollAllDevices() }
    }

    func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    func pollAllDevices() async {
        isPolling = true
        defer { isPolling = false }
        for device in devices { await pollDevice(device) }
    }

    func pollDevice(_ device: IoTDevice) async {
        switch device.connectionProtocol {
        case .http:      await pollHTTP(device)
        case .modbusTCP: await pollModbus(device)
        }
    }

    // MARK: - HTTP polling (ESP32 / RPi)
    // Expected response: {"sensors":[{"id":"t1","name":"Temperature","type":"temperature","value":23.5,"unit":"°C"}]}
    // or flat array: [{"id":"t1",...}]

    private func pollHTTP(_ device: IoTDevice) async {
        let path = device.apiPath.isEmpty ? "/sensors" : device.apiPath
        guard let url = URL(string: "\(device.baseURL)\(path)") else { return }
        do {
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: req)
            parseHTTPResponse(data, deviceId: device.id)
            markConnected(device.id, connected: true)
        } catch {
            markConnected(device.id, connected: false)
        }
    }

    private func parseHTTPResponse(_ data: Data, deviceId: UUID) {
        let raw: [[String: Any]]
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = obj["sensors"] as? [[String: Any]] {
            raw = arr
        } else if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            raw = arr
        } else { return }

        for item in raw {
            let remoteId = item["id"] as? String ?? item["name"] as? String ?? UUID().uuidString
            let rawValue = (item["value"] as? Double) ?? (item["value"] as? Int).map(Double.init)
            let name     = item["name"] as? String ?? remoteId
            let typeStr  = item["type"] as? String ?? ""
            let unit     = item["unit"] as? String ?? ""
            let sensorType = IoTSensor.SensorType(rawValue: typeStr) ?? .custom

            if let idx = sensors.firstIndex(where: { $0.deviceId == deviceId && $0.remoteId == remoteId }) {
                sensors[idx].value = rawValue
                sensors[idx].lastUpdated = Date()
            } else {
                sensors.append(IoTSensor(
                    deviceId: deviceId, remoteId: remoteId, name: name,
                    type: sensorType,
                    unit: unit.isEmpty ? sensorType.defaultUnit : unit,
                    value: rawValue, lastUpdated: Date()
                ))
            }
        }
        persist()
        checkAutomations()
    }

    // MARK: - Modbus TCP polling (RS485 gateway)

    private func pollModbus(_ device: IoTDevice) async {
        let deviceSensors = sensorsForDevice(device).filter { $0.modbusAddress != nil }
        guard !deviceSensors.isEmpty else {
            markConnected(device.id, connected: false)
            return
        }
        var anySuccess = false
        for sensor in deviceSensors {
            guard let address = sensor.modbusAddress else { continue }
            if let raw = await readModbusTCPRegister(
                host: device.host, port: device.port,
                unitId: UInt8(clamping: device.unitId),
                address: UInt16(address)
            ) {
                let scaled = Double(raw) * sensor.modbusScale
                if let idx = sensors.firstIndex(where: { $0.id == sensor.id }) {
                    sensors[idx].value = scaled
                    sensors[idx].lastUpdated = Date()
                }
                anySuccess = true
            }
        }
        markConnected(device.id, connected: anySuccess)
        persist()
        checkAutomations()
    }

    // Reads one holding register via Modbus TCP (FC 03)
    private func readModbusTCPRegister(host: String, port: Int, unitId: UInt8, address: UInt16) async -> UInt16? {
        await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? 502
            )
            let connection = NWConnection(to: endpoint, using: .tcp)
            // ONE serial queue for everything that can end this exchange —
            // the connection's callbacks AND the timeout. On two queues the
            // `done` guard raced, and a reply landing right at the deadline
            // could resume the continuation twice (a hard trap).
            let queue = DispatchQueue(label: "prvio.modbus.read")
            var done = false

            func finish(_ result: UInt16?) {
                guard !done else { return }
                done = true
                continuation.resume(returning: result)
                connection.cancel()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Modbus TCP frame: Read Holding Registers (FC 03), 1 register
                    var frame = Data(count: 12)
                    frame[0] = 0x00; frame[1] = 0x01   // Transaction ID
                    frame[2] = 0x00; frame[3] = 0x00   // Protocol ID
                    frame[4] = 0x00; frame[5] = 0x06   // Remaining length
                    frame[6] = unitId                   // Unit ID
                    frame[7] = 0x03                     // FC: Read Holding Registers
                    frame[8] = UInt8(address >> 8)
                    frame[9] = UInt8(address & 0xFF)    // Starting address
                    frame[10] = 0x00; frame[11] = 0x01  // Quantity = 1

                    connection.send(content: frame, completion: .contentProcessed { _ in })
                    connection.receive(minimumIncompleteLength: 9, maximumLength: 256) { data, _, _, _ in
                        var result: UInt16?
                        if let d = data, d.count >= 11 {
                            // MBAP(6) + UnitID(1) + FC(1) + ByteCount(1) + Value(2)
                            result = UInt16(d[9]) << 8 | UInt16(d[10])
                        }
                        finish(result)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 4) { finish(nil) }
        }
    }

    // MARK: - Connection test

    func testConnection(_ device: IoTDevice) async -> Bool {
        switch device.connectionProtocol {
        case .http:
            let path = device.apiPath.isEmpty ? "/sensors" : device.apiPath
            guard let url = URL(string: "\(device.baseURL)\(path)") else { return false }
            do {
                let (_, resp) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 4))
                return (resp as? HTTPURLResponse)?.statusCode == 200
            } catch { return false }
        case .modbusTCP:
            let r = await readModbusTCPRegister(
                host: device.host, port: device.port,
                unitId: UInt8(clamping: device.unitId), address: 0
            )
            return r != nil
        }
    }

    // MARK: - Helpers

    private func markConnected(_ id: UUID, connected: Bool) {
        guard let idx = devices.firstIndex(where: { $0.id == id }) else { return }
        devices[idx].isConnected = connected
        if connected { devices[idx].lastSeen = Date() }
    }

    // MARK: - Automations CRUD

    func addAutomation(_ a: IoTAutomation) { automations.append(a); persist() }

    func removeAutomation(_ a: IoTAutomation) {
        automations.removeAll { $0.id == a.id }; persist()
    }

    func toggleAutomation(_ a: IoTAutomation) {
        if let idx = automations.firstIndex(where: { $0.id == a.id }) {
            automations[idx].isEnabled.toggle(); persist()
        }
    }

    private func checkAutomations() {
        for auto in automations where auto.isEnabled {
            guard let sid = auto.triggerSensorId,
                  let sensor = sensors.first(where: { $0.id == sid }),
                  let value = sensor.value else { continue }
            let fired: Bool
            switch auto.condition {
            case .above:  fired = value > auto.triggerValue
            case .below:  fired = value < auto.triggerValue
            case .equals: fired = abs(value - auto.triggerValue) < 0.1
            }
            if fired { fireAction(auto, sensor: sensor) }
        }
    }

    private func fireAction(_ auto: IoTAutomation, sensor: IoTSensor) {
        switch auto.action {
        case .sendNotification:
            let c = UNMutableNotificationContent()
            c.title = "PRVIO — \(auto.name)"
            c.body = auto.actionPayload.isEmpty
                ? "\(sensor.name): \(sensor.displayValue)"
                : auto.actionPayload
            c.sound = .default
            let req = UNNotificationRequest(
                identifier: "\(auto.id)-\(Int(Date().timeIntervalSince1970))",
                content: c, trigger: nil)
            UNUserNotificationCenter.current().add(req)

        case .callWebhook:
            if let url = URL(string: auto.actionPayload) {
                Task { try? await URLSession.shared.data(from: url) }
            }

        case .createTask:
            NotificationCenter.default.post(
                name: .init("com.prvio.iot.createTask"),
                object: nil,
                userInfo: [
                    "automationName": auto.name,
                    "sensorValue": sensor.displayValue,
                    "sensorName": sensor.name
                ]
            )
        }
    }
}
