import SwiftUI
import UIKit

// Generates a PDF care sheet for one plant and shares it (mirrors
// ElementPDFExporter: same page size, margins and drawing approach, with a
// page break added because a care sheet can outgrow one page).
//
// Honesty law (Plant OS): every line renders only when the underlying value
// actually exists — missing data is omitted, never replaced by a placeholder.

enum PlantPDFExporter {
    /// Renders the care sheet. `species` is the plant's linked encyclopedia
    /// entry (if any) and `events` is whatever history the caller already has
    /// loaded — no fetching happens here.
    static func makePDF(for plant: Plant,
                        species: PlantSpeciesEntry?,
                        events: [PlantEvent]) -> URL? {
        let pageW: CGFloat = 612, pageH: CGFloat = 792
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let safeName = plant.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "plant" : safeName).pdf")

        let sections = buildSections(plant: plant, species: species, events: events)

        do {
            try renderer.writePDF(to: url) { ctx in
                ctx.beginPage()
                var y: CGFloat = 48
                let left: CGFloat = 48
                let width = pageW - 96

                func draw(_ s: String, font: UIFont, color: UIColor = .black, gap: CGFloat = 8) {
                    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let bounding = (s as NSString).boundingRect(
                        with: CGSize(width: width, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
                    if y + bounding.height > pageH - 48 {
                        ctx.beginPage()
                        y = 48
                    }
                    (s as NSString).draw(in: CGRect(x: left, y: y, width: width, height: bounding.height + 4),
                                         withAttributes: attr)
                    y += bounding.height + gap
                }

                // Header: emoji + name, species/latin, sheet subtitle.
                draw("\(plant.emoji) \(plant.name)", font: .boldSystemFont(ofSize: 24))
                if let species = plant.species ?? plant.latinName, !species.isEmpty {
                    draw(species, font: .italicSystemFont(ofSize: 14), color: .darkGray, gap: 4)
                }
                draw(String(localized: "plant_pdf_care_sheet"), font: .systemFont(ofSize: 12),
                     color: .gray, gap: 4)
                if let location = plant.location, !location.isEmpty {
                    draw("\(String(localized: "Location")): \(location)",
                         font: .systemFont(ofSize: 12), color: .gray)
                }

                for section in sections {
                    y += 10
                    draw(section.title, font: .boldSystemFont(ofSize: 15), gap: 6)
                    for line in section.lines {
                        draw(line, font: .systemFont(ofSize: 13))
                    }
                }

                y += 10
                draw(String(localized: "plant_pdf_generated"), font: .systemFont(ofSize: 10), color: .lightGray)
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: Content assembly (only real data survives)

    private struct Section {
        let title: String
        let lines: [String]
    }

    private static func buildSections(plant: Plant,
                                      species: PlantSpeciesEntry?,
                                      events: [PlantEvent]) -> [Section] {
        var sections: [Section] = []

        // General information (P1 fields).
        var general: [String] = []
        appendLine(&general, "plant_gi_nickname", plant.nickname)
        appendLine(&general, "plant_gi_latin", plant.latinName)
        appendLine(&general, "plant_gi_family", plant.botanicalFamily)
        appendLine(&general, "plant_gi_genus", plant.genus)
        appendLine(&general, "plant_gi_cultivar", plant.cultivar)
        appendLine(&general, "plant_gi_origin", plant.origin)
        appendLine(&general, "plant_gi_climate", plant.climateZone)
        appendLine(&general, "plant_gi_placement", plant.placementLabel)
        let toxicity = plant.toxicitySummary
        if !toxicity.isEmpty {
            general.append(String(format: String(localized: "plant_tox_fmt"),
                                  toxicity.joined(separator: ", ")))
        }
        if !general.isEmpty {
            sections.append(Section(title: String(localized: "plant_gi_title"), lines: general))
        }

        // Care requirements from the linked encyclopedia entry (P3 bands).
        if let e = species {
            var care: [String] = []
            appendLine(&care, "plant_care_light", lightBand(e))
            appendLine(&care, "plant_care_temperature", tempBand(e))
            appendLine(&care, "plant_care_humidity", humidityBand(e))
            appendLine(&care, "plant_care_spring", e.waterSpring)
            appendLine(&care, "plant_care_summer", e.waterSummer)
            appendLine(&care, "plant_care_autumn", e.waterAutumn)
            appendLine(&care, "plant_care_winter", e.waterWinter)
            if let topcm = e.waterTopCm {
                care.append(String(format: String(localized: "plant_care_topcm_fmt"), topcm))
            }
            appendLine(&care, "plant_care_fert_type", e.fertilizerType)
            appendLine(&care, "plant_care_fert_npk", e.fertilizerNpk)
            appendLine(&care, "plant_care_fert_freq", e.fertilizerFreq)
            if e.fertilizerWinterPause == true {
                care.append(String(localized: "plant_care_winter_pause"))
            }
            appendLine(&care, "plant_care_repot_interval", e.repotInterval)
            appendLine(&care, "plant_care_repot_period", e.repotPeriod)
            if !care.isEmpty {
                sections.append(Section(title: String(localized: "plant_care_title"), lines: care))
            }
        }

        // Watering: the plant's own cadence + last watered.
        let watering = [
            "\(String(localized: "Watering interval")): " +
                Plant.wateringIntervalDisplay(plant.wateringIntervalDays),
            "\(String(localized: "Last watered")): \(plant.lastWateredDisplay)",
        ]
        sections.append(Section(title: String(localized: "plant_care_watering"), lines: watering))

        // Recent history: the newest logged care events the caller already has.
        let recent = events
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(10)
            .map { event -> String in
                var line = kindLabel(event.kindEnum)
                if let d = event.date {
                    line = "\(AppDateDisplay.dayMonthYear.string(from: d)) — \(line)"
                }
                if let note = event.noteText {
                    line += " — \(note)"
                }
                return line
            }
        if !recent.isEmpty {
            sections.append(Section(title: String(localized: "plant_pdf_recent_history"),
                                    lines: Array(recent)))
        }

        return sections
    }

    /// Appends "Label: value" when a real value exists; skips otherwise.
    private static func appendLine(_ lines: inout [String],
                                   _ key: String.LocalizationValue,
                                   _ value: String?) {
        guard let value, !value.isEmpty else { return }
        lines.append("\(String(localized: key)): \(value)")
    }

    // MARK: Band formatting (mirrors PlantCareView's honest formatting)

    private static func lightBand(_ e: PlantSpeciesEntry) -> String? {
        let unit = "lux"
        if let mn = e.lightLuxMin, let mx = e.lightLuxMax {
            var s = "\(mn)–\(mx) \(unit)"
            if let id = e.lightLuxIdeal {
                s += " · " + String(format: String(localized: "plant_care_ideal_fmt"), "\(id) \(unit)")
            }
            return s
        }
        if let id = e.lightLuxIdeal {
            return String(format: String(localized: "plant_care_ideal_fmt"), "\(id) \(unit)")
        }
        if let mn = e.lightLuxMin { return "≥ \(mn) \(unit)" }
        if let mx = e.lightLuxMax { return "≤ \(mx) \(unit)" }
        return nil
    }

    private static func tempBand(_ e: PlantSpeciesEntry) -> String? {
        func n(_ v: Double) -> String {
            v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
        }
        var parts: [String] = []
        if let mn = e.tempIdealMin, let mx = e.tempIdealMax {
            parts.append(String(format: String(localized: "plant_care_ideal_fmt"),
                                "\(n(mn))–\(n(mx)) °C"))
        }
        if let mn = e.tempAcceptedMin, let mx = e.tempAcceptedMax {
            parts.append(String(format: String(localized: "plant_care_accepted_fmt"),
                                "\(n(mn))–\(n(mx)) °C"))
        }
        var danger: [String] = []
        if let lo = e.tempDangerLow { danger.append("< \(n(lo)) °C") }
        if let hi = e.tempDangerHigh { danger.append("> \(n(hi)) °C") }
        if !danger.isEmpty {
            parts.append(String(format: String(localized: "plant_care_danger_fmt"),
                                danger.joined(separator: " / ")))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func humidityBand(_ e: PlantSpeciesEntry) -> String? {
        var parts: [String] = []
        if let mn = e.humidityIdealMin, let mx = e.humidityIdealMax {
            parts.append(String(format: String(localized: "plant_care_ideal_fmt"), "\(mn)–\(mx)%"))
        }
        if let mn = e.humidityAcceptedMin, let mx = e.humidityAcceptedMax {
            parts.append(String(format: String(localized: "plant_care_accepted_fmt"), "\(mn)–\(mx)%"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func kindLabel(_ kind: PlantEventKind) -> String {
        switch kind {
        case .watered:    return String(localized: "plant_evt_watered")
        case .fertilized: return String(localized: "plant_evt_fertilized")
        case .repotted:   return String(localized: "plant_evt_repotted")
        case .sprayed:    return String(localized: "plant_evt_sprayed")
        case .treated:    return String(localized: "plant_evt_treated")
        case .pruned:     return String(localized: "plant_evt_pruned")
        case .note:       return String(localized: "plant_evt_note")
        }
    }
}
