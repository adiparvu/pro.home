import SwiftUI

// MARK: - Plant care requirements + live sensor comparison (Plant OS P3)
//
// The Care surface of the plant page. It renders a linked species' NUMERIC
// requirements — light, temperature, humidity, soil pH, substrate mix,
// watering per season, fertilising, repotting — showing only the fields that
// are actually populated. Honesty law (central to this phase):
//
//   • If a real IoT sensor is bound to a metric (light/temperature/humidity)
//     and this device knows it, a live comparison line shows the reading with
//     an in-range / too-low / too-high verdict.
//   • If nothing is bound (or the bound sensor is not reachable here), the
//     requirement is shown ALONE — never a fabricated or estimated reading.
//   • A species with no care data at all gets a gentle empty state.

extension PlantDetailSheet {
    /// Rendered only when a species is linked (so requirements exist to show).
    /// The card itself degrades to an empty state if that species carries no
    /// care data yet.
    @ViewBuilder
    var careCard: some View {
        let currentId = plantService.plants.first(where: { $0.id == plant.id })?.speciesId ?? plant.speciesId
        if let entry = speciesService.species(id: currentId) {
            PlantCareCard(entry: entry, plant: plant, sensorService: plantSensorService)
        }
    }
}

struct PlantCareCard: View {
    let entry: PlantSpeciesEntry
    let plant: Plant
    let sensorService: PlantSensorService

    private let luxUnit = "lux"
    private let tempUnit = "°C"
    private let humidityUnit = "%"

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Label("plant_care_title", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.secondaryTextColor)

                if !entry.hasCareData {
                    careEmptyState
                } else {
                    if entry.hasLightData { lightSection }
                    if entry.hasTempData { temperatureSection }
                    if entry.hasHumidityData { humiditySection }
                    if entry.hasPhData { phSection }
                    if let mix = entry.substrateMix, !mix.isEmpty { substrateSection(mix) }
                    if entry.hasWaterData { wateringSection }
                    if hasFertiliserData { fertiliserSection }
                    if hasRepotData { repottingSection }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Empty state

    private var careEmptyState: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "leaf")
                .font(AppFont.caption)
                .foregroundStyle(Color.secondaryTextColor)
            Text("plant_care_empty")
                .font(AppFont.footnote)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Light

    @ViewBuilder
    private var lightSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(.light)
            if !lightRequirementText.isEmpty {
                valueLine(lightRequirementText)
            }
            liveArea(.light)
        }
    }

    private var lightRequirementText: String {
        if let mn = entry.lightLuxMin, let mx = entry.lightLuxMax {
            var s = "\(g(mn))–\(g(mx)) \(luxUnit)"
            if let id = entry.lightLuxIdeal {
                s += " · " + String(format: String(localized: "plant_care_ideal_fmt"), "\(g(id)) \(luxUnit)")
            }
            return s
        }
        if let id = entry.lightLuxIdeal {
            return String(format: String(localized: "plant_care_ideal_fmt"), "\(g(id)) \(luxUnit)")
        }
        if let mn = entry.lightLuxMin { return "≥ \(g(mn)) \(luxUnit)" }
        if let mx = entry.lightLuxMax { return "≤ \(g(mx)) \(luxUnit)" }
        return ""
    }

    // MARK: - Temperature

    @ViewBuilder
    private var temperatureSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(.temperature)
            if let ideal = tempIdealText { valueLine(ideal) }
            TemperatureBandBar(entry: entry,
                               live: resolvedSensor(.temperature)?.value)
                .padding(.top, 2)
            if let caption = tempRangeCaption { captionLine(caption) }
            liveArea(.temperature)
        }
    }

    private var tempIdealText: String? {
        if let mn = entry.tempIdealMin, let mx = entry.tempIdealMax { return "\(n(mn))–\(n(mx)) \(tempUnit)" }
        if let mn = entry.tempIdealMin { return "≥ \(n(mn)) \(tempUnit)" }
        if let mx = entry.tempIdealMax { return "≤ \(n(mx)) \(tempUnit)" }
        return nil
    }

    private var tempRangeCaption: String? {
        var parts: [String] = []
        if let mn = entry.tempAcceptedMin, let mx = entry.tempAcceptedMax {
            parts.append(String(format: String(localized: "plant_care_accepted_fmt"), "\(n(mn))–\(n(mx)) \(tempUnit)"))
        }
        var danger: [String] = []
        if let lo = entry.tempDangerLow { danger.append("< \(n(lo)) \(tempUnit)") }
        if let hi = entry.tempDangerHigh { danger.append("> \(n(hi)) \(tempUnit)") }
        if !danger.isEmpty {
            parts.append(String(format: String(localized: "plant_care_danger_fmt"), danger.joined(separator: " / ")))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Humidity

    @ViewBuilder
    private var humiditySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(.humidity)
            if let ideal = humidityIdealText { valueLine(ideal) }
            if let caption = humidityCaption { captionLine(caption) }
            liveArea(.humidity)
        }
    }

    private var humidityIdealText: String? {
        if let mn = entry.humidityIdealMin, let mx = entry.humidityIdealMax { return "\(mn)–\(mx)\(humidityUnit)" }
        if let mn = entry.humidityIdealMin { return "≥ \(mn)\(humidityUnit)" }
        if let mx = entry.humidityIdealMax { return "≤ \(mx)\(humidityUnit)" }
        return nil
    }

    private var humidityCaption: String? {
        guard let mn = entry.humidityAcceptedMin, let mx = entry.humidityAcceptedMax else { return nil }
        return String(format: String(localized: "plant_care_accepted_fmt"), "\(mn)–\(mx)\(humidityUnit)")
    }

    // MARK: - Soil pH (no sensor; requirement only)

    @ViewBuilder
    private var phSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("plant_care_ph", systemImage: "drop.circle")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.accentColor)
            if let text = phText { valueLine(text) }
        }
    }

    private var phText: String? {
        if let mn = entry.phMin, let mx = entry.phMax {
            var s = "\(n(mn))–\(n(mx))"
            if let id = entry.phIdeal { s += " · " + String(format: String(localized: "plant_care_ideal_fmt"), n(id)) }
            return s
        }
        if let id = entry.phIdeal { return String(format: String(localized: "plant_care_ideal_fmt"), n(id)) }
        return nil
    }

    // MARK: - Substrate

    @ViewBuilder
    private func substrateSection(_ mix: [String: Int]) -> some View {
        let items = mix.sorted { $0.value > $1.value }
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("plant_care_substrate", systemImage: "square.stack.3d.up.fill")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.accentColor)

            SubstrateBar(segments: items.enumerated().map { (Double($0.element.value), substrateColor($0.offset)) })
                .frame(height: 10)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(spacing: AppSpacing.sm) {
                        Circle().fill(substrateColor(idx)).frame(width: 8, height: 8)
                        substrateName(item.key)
                            .font(AppFont.footnote)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(item.value)%")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                    }
                }
            }
        }
    }

    private func substrateColor(_ index: Int) -> Color {
        let palette: [Color] = [.brandSuccess, .brandTeal, .brandSkyBlue, .brandGold, .brandWarning, .brandPurple]
        return palette[index % palette.count]
    }

    private func substrateName(_ key: String) -> Text {
        switch key {
        case "peat":         return Text("plant_care_sub_peat")
        case "coco":         return Text("plant_care_sub_coco")
        case "perlite":      return Text("plant_care_sub_perlite")
        case "bark":         return Text("plant_care_sub_bark")
        case "sand":         return Text("plant_care_sub_sand")
        case "potting_soil": return Text("plant_care_sub_potting_soil")
        case "compost":      return Text("plant_care_sub_compost")
        case "pumice":       return Text("plant_care_sub_pumice")
        default:             return Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }

    // MARK: - Watering

    @ViewBuilder
    private var wateringSection: some View {
        let seasons: [(LocalizedStringKey, String, String?)] = [
            ("plant_care_spring", "leaf", entry.waterSpring),
            ("plant_care_summer", "sun.max", entry.waterSummer),
            ("plant_care_autumn", "wind", entry.waterAutumn),
            ("plant_care_winter", "snowflake", entry.waterWinter),
        ]
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("plant_care_watering", systemImage: "drop.fill")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.accentColor)

            ForEach(Array(seasons.enumerated()), id: \.offset) { _, season in
                if let note = season.2, !note.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        Image(systemName: season.1)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.secondaryTextColor)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(season.0)
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(.primary)
                            Text(note)
                                .font(AppFont.footnote)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let topcm = entry.waterTopCm {
                captionLine(String(format: String(localized: "plant_care_topcm_fmt"), topcm))
            }
        }
    }

    // MARK: - Fertilising

    private var hasFertiliserData: Bool {
        entry.fertilizerType != nil || entry.fertilizerNpk != nil || entry.fertilizerFreq != nil
            || entry.fertilizerMonths?.isEmpty == false || entry.fertilizerWinterPause == true
    }

    @ViewBuilder
    private var fertiliserSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("plant_care_fertilising", systemImage: "leaf.arrow.triangle.circlepath")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.accentColor)

            if let type = entry.fertilizerType, !type.isEmpty { keyValue("plant_care_fert_type", type) }
            if let npk = entry.fertilizerNpk, !npk.isEmpty { keyValue("plant_care_fert_npk", npk) }
            if let freq = entry.fertilizerFreq, !freq.isEmpty { keyValue("plant_care_fert_freq", freq) }
            if let months = entry.fertilizerMonths, !months.isEmpty {
                keyValue("plant_care_fert_months", localizedMonths(months))
            }
            if entry.fertilizerWinterPause == true {
                captionLine(String(localized: "plant_care_winter_pause"))
            }
        }
    }

    // MARK: - Repotting

    private var hasRepotData: Bool {
        entry.repotInterval != nil || entry.repotPeriod != nil
            || entry.repotPotStepCm != nil || entry.repotPotMaxCm != nil
    }

    @ViewBuilder
    private var repottingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("plant_care_repotting", systemImage: "arrow.up.bin.fill")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.accentColor)

            if let interval = entry.repotInterval, !interval.isEmpty { keyValue("plant_care_repot_interval", interval) }
            if let period = entry.repotPeriod, !period.isEmpty { keyValue("plant_care_repot_period", period) }
            if let step = entry.repotPotStepCm {
                keyValue("plant_care_repot_step", String(format: String(localized: "plant_care_cm_fmt"), step))
            }
            if let maxCm = entry.repotPotMaxCm {
                keyValue("plant_care_repot_max", String(format: String(localized: "plant_care_cm_fmt"), maxCm))
            }
        }
    }

    // MARK: - Live comparison + binding affordance (shared by the 3 metrics)

    /// The sensor bound to `metric`, resolved to a live sensor known to THIS
    /// device — nil when nothing is bound or the bound sensor is not present
    /// here (never fabricates a reading).
    private func resolvedSensor(_ metric: PlantCareMetric) -> IoTSensor? {
        guard let binding = sensorService.binding(for: metric) else { return nil }
        return IoTService.shared.sensor(forRef: binding.sensorRef)
    }

    @ViewBuilder
    private func liveArea(_ metric: PlantCareMetric) -> some View {
        let binding = sensorService.binding(for: metric)
        if let sensor = resolvedSensor(metric), let v = sensor.value {
            liveComparison(metric, sensor: sensor, value: v)
        } else if binding != nil {
            captionLine(String(localized: "plant_care_sensor_unavailable"))
        } else {
            captionLine(String(localized: "plant_care_no_sensor"))
        }
    }

    @ViewBuilder
    private func liveComparison(_ metric: PlantCareMetric, sensor: IoTSensor, value: Double) -> some View {
        let comp = comparison(metric, value)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: comp?.icon ?? "dot.circle.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(comp?.color ?? .secondary)
                Text(receivesText(metric, value))
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppSpacing.xs)
                if let comp {
                    Text(comp.word)
                        .font(AppFont.label)
                        .foregroundStyle(comp.color)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 3)
                        .background(comp.color.opacity(0.14), in: Capsule())
                }
            }
            if let updated = sensor.lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(AppFont.scaled(9))
                    Text(updated, format: .relative(presentation: .named))
                }
                .font(AppFont.caption2)
                .foregroundStyle(Color.secondaryTextColor)
            }
        }
        .padding(.top, 1)
    }

    // MARK: Section header with the bind-a-sensor control

    @ViewBuilder
    private func sectionHeader(_ metric: PlantCareMetric) -> some View {
        let binding = sensorService.binding(for: metric)
        let available = IoTService.shared.sensors(for: metric)
        HStack {
            Label(metric.title, systemImage: metric.icon)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.accentColor)
            Spacer()
            if binding != nil || !available.isEmpty {
                Menu {
                    ForEach(available) { sensor in
                        Button {
                            HapticFeedback.selection()
                            Task {
                                await sensorService.bind(plantId: plant.id, propertyId: plant.propertyId,
                                                         sensorRef: sensor.stableRef, metric: metric)
                            }
                        } label: {
                            Label("\(sensor.name) · \(sensor.displayValue)", systemImage: sensor.type.icon)
                        }
                    }
                    if available.isEmpty {
                        Label("plant_care_no_sensors_available", systemImage: "sensor.tag.radiowaves.forward.fill")
                    }
                    if let binding {
                        Divider()
                        Button(role: .destructive) {
                            HapticFeedback.impact(.light)
                            Task { await sensorService.unbind(binding) }
                        } label: {
                            Label("plant_care_unbind", systemImage: "link.badge.minus")
                        }
                    }
                } label: {
                    if binding != nil {
                        Image(systemName: "ellipsis.circle")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(Color.secondaryTextColor)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                            Text("plant_care_bind")
                        }
                        .font(AppFont.caption)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    // MARK: - Comparison verdicts

    private func comparison(_ metric: PlantCareMetric, _ v: Double) -> CareComparison? {
        switch metric {
        case .light:       return lightComparison(v)
        case .temperature: return tempComparison(v)
        case .humidity:    return humidityComparison(v)
        }
    }

    private func lightComparison(_ v: Double) -> CareComparison? {
        guard entry.hasLightData else { return nil }
        if let mx = entry.lightLuxMax, v > Double(mx) { return CareComparison(.high, danger: false) }
        if let mn = entry.lightLuxMin, v < Double(mn) { return CareComparison(.low, danger: false) }
        return CareComparison(.ideal, danger: false)
    }

    private func humidityComparison(_ v: Double) -> CareComparison? {
        guard entry.hasHumidityData else { return nil }
        if let iMin = entry.humidityIdealMin, let iMax = entry.humidityIdealMax,
           v >= Double(iMin), v <= Double(iMax) { return CareComparison(.ideal, danger: false) }
        let aMin = entry.humidityAcceptedMin ?? entry.humidityIdealMin
        let aMax = entry.humidityAcceptedMax ?? entry.humidityIdealMax
        if let aMin, v < Double(aMin) { return CareComparison(.low, danger: false) }
        if let aMax, v > Double(aMax) { return CareComparison(.high, danger: false) }
        return CareComparison(.accepted, danger: false)
    }

    private func tempComparison(_ v: Double) -> CareComparison? {
        guard entry.hasTempData else { return nil }
        if let lo = entry.tempDangerLow, v < lo { return CareComparison(.low, danger: true) }
        if let hi = entry.tempDangerHigh, v > hi { return CareComparison(.high, danger: true) }
        if let iMin = entry.tempIdealMin, let iMax = entry.tempIdealMax,
           v >= iMin, v <= iMax { return CareComparison(.ideal, danger: false) }
        let aMin = entry.tempAcceptedMin ?? entry.tempIdealMin
        let aMax = entry.tempAcceptedMax ?? entry.tempIdealMax
        if let aMin, v < aMin { return CareComparison(.low, danger: false) }
        if let aMax, v > aMax { return CareComparison(.high, danger: false) }
        return CareComparison(.accepted, danger: false)
    }

    // MARK: - Reading + ideal summaries for the live line

    private func receivesText(_ metric: PlantCareMetric, _ v: Double) -> String {
        let reading = readingText(metric, v)
        let ideal = idealSummary(metric)
        if ideal.isEmpty { return String(format: String(localized: "plant_care_receives_only_fmt"), reading) }
        return String(format: String(localized: "plant_care_receives_fmt"), reading, ideal)
    }

    private func readingText(_ metric: PlantCareMetric, _ v: Double) -> String {
        switch metric {
        case .light:       return "\(g(Int(v.rounded()))) \(luxUnit)"
        case .temperature: return "\(n(v)) \(tempUnit)"
        case .humidity:    return "\(Int(v.rounded()))\(humidityUnit)"
        }
    }

    private func idealSummary(_ metric: PlantCareMetric) -> String {
        switch metric {
        case .light:
            if let id = entry.lightLuxIdeal { return "\(g(id)) \(luxUnit)" }
            if let mn = entry.lightLuxMin, let mx = entry.lightLuxMax { return "\(g(mn))–\(g(mx)) \(luxUnit)" }
            return ""
        case .temperature:
            return tempIdealText ?? ""
        case .humidity:
            return humidityIdealText ?? ""
        }
    }

    // MARK: - Small building blocks

    private func valueLine(_ text: String) -> some View {
        Text(text)
            .font(AppFont.subheadline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func captionLine(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(Color.secondaryTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyValue(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(AppFont.footnote)
                .foregroundStyle(Color.secondaryTextColor)
            Spacer(minLength: AppSpacing.sm)
            Text(value)
                .font(AppFont.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Formatting helpers

    /// Locale-grouped integer ("1,200" / "1.200").
    private func g(_ i: Int) -> String { i.formatted() }

    /// Locale number with up to one fraction digit, trailing zero dropped
    /// ("18", "6.5" / "6,5").
    private func n(_ d: Double) -> String { d.formatted(.number.precision(.fractionLength(0...1))) }

    /// English month keys → localized month names, joined for display.
    private func localizedMonths(_ months: [String]) -> String {
        let en = DateFormatter(); en.locale = Locale(identifier: "en_US_POSIX")
        let loc = DateFormatter(); loc.locale = .current
        let enSyms: [String] = en.monthSymbols
        let locSyms: [String] = loc.monthSymbols
        let mapped = months.map { m -> String in
            if let i = enSyms.firstIndex(where: { $0.caseInsensitiveCompare(m) == .orderedSame }), i < locSyms.count {
                return locSyms[i]
            }
            return m
        }
        return mapped.joined(separator: ", ")
    }
}

// MARK: - Comparison verdict

struct CareComparison {
    enum Verdict { case ideal, accepted, low, high }
    let verdict: Verdict
    let danger: Bool

    init(_ verdict: Verdict, danger: Bool) {
        self.verdict = verdict
        self.danger = danger
    }

    var color: Color {
        switch verdict {
        case .ideal:    return .brandSuccess
        case .accepted: return .brandSkyBlue
        case .low, .high: return danger ? .brandDanger : .brandWarning
        }
    }

    var word: LocalizedStringKey {
        switch verdict {
        case .ideal:    return "plant_care_in_range"
        case .accepted: return "plant_care_accepted_state"
        case .low:      return "plant_care_too_low"
        case .high:     return "plant_care_too_high"
        }
    }

    var icon: String {
        switch verdict {
        case .ideal:    return "checkmark.circle.fill"
        case .accepted: return "checkmark.circle"
        case .low:      return "arrow.down.circle.fill"
        case .high:     return "arrow.up.circle.fill"
        }
    }
}

// MARK: - Temperature comfort/danger band bar
//
// A single horizontal track coloured danger → accepted → ideal → accepted →
// danger across the species' thresholds, with a marker at the live reading (if
// any). Uses one GeometryReader — necessary to map a temperature to an x offset.

private struct TemperatureBandBar: View {
    let entry: PlantSpeciesEntry
    let live: Double?

    var body: some View {
        let lo = entry.tempDangerLow ?? entry.tempAcceptedMin ?? entry.tempIdealMin
        let hi = entry.tempDangerHigh ?? entry.tempAcceptedMax ?? entry.tempIdealMax
        Group {
            if let lo, let hi, hi > lo {
                GeometryReader { geo in
                    let w = geo.size.width
                    let span = hi - lo
                    let segs = segments(lo: lo, hi: hi)
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                                Rectangle()
                                    .fill(seg.color)
                                    .frame(width: max(0, CGFloat(seg.fraction) * w))
                            }
                        }
                        .frame(height: 8)
                        .clipShape(Capsule())

                        if let live {
                            let clamped = min(max(live, lo), hi)
                            let x = CGFloat((clamped - lo) / span) * w
                            Capsule()
                                .fill(Color.primary)
                                .frame(width: 3, height: 16)
                                .overlay(Capsule().stroke(Color(.systemBackground), lineWidth: 1.5))
                                .position(x: x, y: geo.size.height / 2)
                        }
                    }
                }
                .frame(height: 18)
            }
        }
    }

    private struct Seg { let fraction: Double; let color: Color }

    private func segments(lo: Double, hi: Double) -> [Seg] {
        let span = hi - lo
        // Fall back sensibly when a band is missing so the bar still renders.
        var iMin = entry.tempIdealMin ?? entry.tempAcceptedMin ?? lo
        var iMax = entry.tempIdealMax ?? entry.tempAcceptedMax ?? hi
        var aMin = entry.tempAcceptedMin ?? iMin
        var aMax = entry.tempAcceptedMax ?? iMax
        // Keep boundaries ordered and inside [lo, hi].
        aMin = min(max(aMin, lo), hi)
        iMin = min(max(iMin, aMin), hi)
        iMax = min(max(iMax, iMin), hi)
        aMax = min(max(aMax, iMax), hi)

        let danger = Color.brandDanger.opacity(0.5)
        let accepted = Color.brandSkyBlue.opacity(0.45)
        let ideal = Color.brandSuccess.opacity(0.6)
        return [
            Seg(fraction: (aMin - lo) / span, color: danger),
            Seg(fraction: (iMin - aMin) / span, color: accepted),
            Seg(fraction: (iMax - iMin) / span, color: ideal),
            Seg(fraction: (aMax - iMax) / span, color: accepted),
            Seg(fraction: (hi - aMax) / span, color: danger),
        ]
    }
}

// MARK: - Substrate proportion bar (stacked)

private struct SubstrateBar: View {
    /// (weight, colour) pairs; widths are proportional to weight.
    let segments: [(Double, Color)]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.0 }, 0.0001)
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    Rectangle()
                        .fill(seg.1)
                        .frame(width: max(0, CGFloat(seg.0 / total) * w))
                }
            }
            .clipShape(Capsule())
        }
    }
}
