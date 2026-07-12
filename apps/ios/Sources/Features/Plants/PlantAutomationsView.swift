import SwiftUI

// MARK: - Per-plant automations (Plant OS P6, Level 6)
//
// Lists (and builds) the automation rules tagged to this plant. Every rule
// watches one of the plant's already-bound IoT sensors (P3) and, when a
// threshold is crossed, fires through the EXISTING IoT hub automation engine
// (IoTService) — a single engine, never a second one. Actuation is honest:
// the "Control a device" action drives a real relay through the actuator layer
// or an outbound webhook (Homebridge / Shortcuts); native HomeKit is never
// claimed. A rule whose sensor is not present on this device is shown but
// flagged as running on the device that owns the sensor.

struct PlantAutomationsCard: View {
    let plant: Plant
    let service: PlantAutomationService
    let sensorService: PlantSensorService

    @State private var showAdd = false

    private var boundMetrics: [PlantCareMetric] {
        PlantCareMetric.allCases.filter { sensorService.binding(for: $0) != nil }
    }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Label("plant_auto_title", systemImage: "bolt.badge.automatic")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    Spacer()
                    if !boundMetrics.isEmpty {
                        Button { showAdd = true; HapticFeedback.impact(.light) } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(AppFont.scaled(20)).foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("plant_auto_add")
                    }
                }

                Text("plant_auto_sub")
                    .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if boundMetrics.isEmpty {
                    emptyNoSensors
                } else if service.automations.isEmpty {
                    Text("plant_auto_empty")
                        .font(AppFont.footnote).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(service.automations) { a in
                        row(a)
                        if a.id != service.automations.last?.id { Divider().opacity(0.1) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showAdd) {
            PlantAutomationBuilderSheet(plant: plant, sensorService: sensorService) { payload in
                Task { await service.add(payload) }
            }
        }
    }

    private var emptyNoSensors: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(AppFont.caption).foregroundStyle(.secondary)
            Text("plant_auto_need_sensor")
                .font(AppFont.footnote).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ a: PlantAutomation) -> some View {
        let action = a.actionEnum
        let unit = a.metricEnum.map { PlantAutomationUnits.unit(for: $0) } ?? ""
        HStack(spacing: AppSpacing.md) {
            Image(systemName: action.icon)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(a.isActive ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .glassCircle()
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(a.isActive ? .primary : .secondary)
                HStack(spacing: AppSpacing.xs) {
                    if let m = a.metricEnum {
                        Text(m.title).font(AppFont.caption).foregroundStyle(.secondary)
                    }
                    Text(a.summary(unit: unit)).font(AppFont.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(AppFont.scaled(9)).foregroundStyle(.tertiary)
                    Text(action.title).font(AppFont.caption).foregroundStyle(.secondary)
                }
                if !service.isEvaluatedHere(a) {
                    Label("plant_auto_other_device", systemImage: "iphone.and.arrow.forward")
                        .font(AppFont.caption2).foregroundStyle(.tertiary)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: AppSpacing.sm)
            Toggle("", isOn: Binding(
                get: { a.isActive },
                set: { v in Task { await service.setActive(a, active: v) } }
            ))
            .labelsHidden().scaleEffect(0.8)
            Menu {
                Button(role: .destructive) { Task { await service.delete(a) } } label: {
                    Label("plant_auto_delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(.leading, 2)
            }
            .accessibilityLabel("More")
        }
        .padding(.vertical, AppSpacing.xxs)
        .opacity(a.isActive ? 1 : 0.65)
    }
}

// MARK: - Units helper

enum PlantAutomationUnits {
    static func unit(for metric: PlantCareMetric) -> String {
        switch metric {
        case .light:       return "lux"
        case .temperature: return "°C"
        case .humidity:    return "%"
        }
    }
}

// MARK: - Builder sheet

struct PlantAutomationBuilderSheet: View {
    let plant: Plant
    let sensorService: PlantSensorService
    let onAdd: (NewPlantAutomation) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var metric: PlantCareMetric
    @State private var comparison: PlantAutomationComparison = .below
    @State private var thresholdText: String = ""
    @State private var action: PlantAutomationAction = .notify
    @State private var name: String = ""
    @State private var webhookURL: String = ""
    @State private var actuatorRef: String?

    private let boundMetrics: [PlantCareMetric]

    init(plant: Plant, sensorService: PlantSensorService, onAdd: @escaping (NewPlantAutomation) -> Void) {
        self.plant = plant
        self.sensorService = sensorService
        self.onAdd = onAdd
        let bound = PlantCareMetric.allCases.filter { sensorService.binding(for: $0) != nil }
        self.boundMetrics = bound
        _metric = State(initialValue: bound.first ?? .humidity)
    }

    private var unit: String { PlantAutomationUnits.unit(for: metric) }

    /// The live reading for the selected metric, if this device knows the
    /// bound sensor — shown as context, never invented.
    private var liveReading: Double? {
        guard let b = sensorService.binding(for: metric),
              let s = IoTService.shared.sensor(forRef: b.sensorRef) else { return nil }
        return s.value
    }

    private var relayActuators: [IoTActuator] { IoTService.shared.relayActuators }

    private var canSave: Bool {
        guard Double(normalizedThreshold) != nil else { return false }
        if action == .webhook { return !webhookURL.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    private var normalizedThreshold: String {
        thresholdText.replacingOccurrences(of: ",", with: ".")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.lg) {
                        sensorCard
                        thresholdCard
                        actionCard
                        nameCard
                        Spacer(minLength: AppSpacing.xl)
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle("plant_auto_new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("plant_auto_cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("plant_auto_save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { if thresholdText.isEmpty, let v = liveReading { thresholdText = String(Int(v.rounded())) } }
        }
    }

    // MARK: Sensor selection

    private var sensorCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("plant_auto_when", systemImage: "sensor.tag.radiowaves.forward.fill")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary)
                if boundMetrics.count > 1 {
                    Picker("plant_auto_metric", selection: $metric) {
                        ForEach(boundMetrics) { m in Text(m.title).tag(m) }
                    }
                    .pickerStyle(.segmented)
                } else if let only = boundMetrics.first {
                    Label(only.title, systemImage: only.icon)
                        .font(AppFont.subheadline).foregroundStyle(.primary)
                }
                if let v = liveReading {
                    Text(String(format: String(localized: "plant_auto_live_fmt"),
                                v.formatted(.number.precision(.fractionLength(0...1))), unit))
                        .font(AppFont.caption).foregroundStyle(.secondary)
                } else {
                    Text("plant_auto_sensor_here_missing")
                        .font(AppFont.caption).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Threshold

    private var thresholdCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("plant_auto_threshold", systemImage: "slider.horizontal.3")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary)
                Picker("plant_auto_comparison", selection: $comparison) {
                    ForEach(PlantAutomationComparison.allCases) { c in
                        Text(c.title).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    TextField("0", text: $thresholdText)
                        .keyboardType(.decimalPad)
                        .font(AppFont.title3)
                        .tint(.accentColor)
                    Text(unit).font(AppFont.subheadline).foregroundStyle(.secondary)
                }
                .padding(AppSpacing.md)
                .background(Color.primary.opacity(AppOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Action

    private var actionCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("plant_auto_then", systemImage: "bolt.fill")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary)
                ForEach(PlantAutomationAction.allCases) { opt in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { action = opt }
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: opt.icon)
                                .font(AppFont.footnote).foregroundStyle(action == opt ? Color.accentColor : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(opt.title).font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                                Text(opt.honestyNote).font(AppFont.caption2).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if action == opt {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(AppFont.footnote).foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, AppSpacing.xxs)
                    }
                    .buttonStyle(.plain)
                }

                if action == .webhook || action == .device {
                    TextField("plant_auto_webhook_ph", text: $webhookURL)
                        .font(AppFont.footnote)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .tint(.accentColor)
                        .padding(AppSpacing.md)
                        .background(Color.primary.opacity(AppOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }

                if action == .device {
                    if relayActuators.isEmpty {
                        Text("plant_auto_no_relay")
                            .font(AppFont.caption).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Menu {
                            Button("plant_auto_relay_none") { actuatorRef = nil }
                            ForEach(relayActuators) { act in
                                Button(act.name) { actuatorRef = "\(act.deviceId.uuidString):\(act.remoteId)" }
                            }
                        } label: {
                            HStack {
                                Label("plant_auto_relay", systemImage: "power")
                                    .font(AppFont.footnote).foregroundStyle(.primary)
                                Spacer()
                                Text(selectedRelayName).font(AppFont.caption).foregroundStyle(.secondary)
                                Image(systemName: "chevron.up.chevron.down").font(AppFont.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Rule name

    /// Optional custom name. `save()` always supported one, but no field was
    /// bound to `name`, so every rule silently took the auto-generated
    /// default — which now doubles as the placeholder, so the fallback is
    /// visible rather than implied.
    private var nameCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("plant_auto_name", systemImage: "tag")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary)
                TextField(defaultName, text: $name)
                    .font(AppFont.footnote)
                    .tint(.accentColor)
                    .padding(AppSpacing.md)
                    .background(Color.primary.opacity(AppOpacity.subtleFill),
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedRelayName: String {
        guard let ref = actuatorRef,
              let act = relayActuators.first(where: { "\($0.deviceId.uuidString):\($0.remoteId)" == ref })
        else { return String(localized: "plant_auto_relay_none") }
        return act.name
    }

    // MARK: Save

    private func save() {
        guard let threshold = Double(normalizedThreshold),
              let binding = sensorService.binding(for: metric) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmedName.isEmpty ? defaultName : trimmedName
        let payload = NewPlantAutomation(
            plantId: plant.id,
            propertyId: plant.propertyId,
            name: finalName,
            sensorRef: binding.sensorRef,
            metric: metric.rawValue,
            comparison: comparison.rawValue,
            threshold: threshold,
            action: action.wire,
            actionPayload: payloadValue,
            actuatorRef: action == .device ? actuatorRef : nil,
            isActive: true)
        onAdd(payload)
        HapticFeedback.success()
        dismiss()
    }

    private var payloadValue: String? {
        switch action {
        case .webhook, .device:
            let t = webhookURL.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        default:
            return nil
        }
    }

    private var defaultName: String {
        let metricName = String(localized: metric.titleKey)
        return String(format: String(localized: "plant_auto_default_name_fmt"), plant.name, metricName)
    }
}

// Small bridge so the builder can build a plain String from the metric title.
private extension PlantCareMetric {
    var titleKey: String.LocalizationValue {
        switch self {
        case .light:       return "plant_care_light"
        case .temperature: return "plant_care_temperature"
        case .humidity:    return "plant_care_humidity"
        }
    }
}
