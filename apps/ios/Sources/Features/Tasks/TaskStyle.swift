import SwiftUI

// MARK: - Task presentation style
//
// View-level styling for a task's priority and category — colours, glyphs and
// localized labels shared verbatim by the list rows, the stat header, the
// editor chips and the live preview so every surface stays in lock-step.
//
// This is presentation only: it never touches the persisted `priority` /
// `category` raw strings (business logic keeps owning those). The colour ramp
// here (low → green, medium → purple, high → orange, critical → red) is the
// Tasks module's own visual language and intentionally differs from the
// generic `MaintenanceTask.priorityColor` used by other features.

enum TaskPriorityStyle: String, CaseIterable, Identifiable {
    case low, medium, high, critical

    var id: String { rawValue }

    /// The four raw values persisted by the model, in ascending order.
    static let order = ["low", "medium", "high", "critical"]

    init(_ raw: String) {
        self = TaskPriorityStyle(rawValue: raw) ?? .medium
    }

    var color: Color {
        switch self {
        case .low:      return .brandSuccess
        case .medium:   return .brandPurple
        case .high:     return .brandWarning
        case .critical: return .brandDanger
        }
    }

    /// Localized display label (reuses the established priority keys).
    var label: LocalizedStringKey {
        switch self {
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }

    /// The ascending signal-bars glyph shown before the label.
    var icon: String { "chart.bar.fill" }
}

enum TaskCategoryStyle: String, CaseIterable, Identifiable {
    case maintenance, repair, inspection, cleaning, upgrade, administrative, other

    var id: String { rawValue }

    init(_ raw: String) {
        self = TaskCategoryStyle(rawValue: raw) ?? .other
    }

    var icon: String {
        switch self {
        case .maintenance:   return "wrench.and.screwdriver.fill"
        case .repair:        return "hammer.fill"
        case .inspection:    return "magnifyingglass"
        case .cleaning:      return "sparkles"
        case .upgrade:       return "arrow.up"
        case .administrative:return "doc.text.fill"
        case .other:         return "tag.fill"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .maintenance:   return "Maintenance"
        case .repair:        return "Repair"
        case .inspection:    return "Inspection"
        case .cleaning:      return "Cleaning"
        case .upgrade:       return "Upgrade"
        case .administrative:return "Administrative"
        case .other:         return "Other"
        }
    }
}

// MARK: - Convenience accessors on the model

extension MaintenanceTask {
    var priorityStyle: TaskPriorityStyle { TaskPriorityStyle(priority) }
    var categoryStyle: TaskCategoryStyle { TaskCategoryStyle(category) }
}

// MARK: - Shared motion

extension Animation {
    /// The Tasks module's signature spring — used for every card morph,
    /// section collapse and counter roll so the whole surface animates as one.
    static let taskSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)
}

// MARK: - Small reusable pills

/// The tinted priority pill (bars glyph + label) used in list rows and the
/// preview's mini list card.
struct PriorityPill: View {
    let style: TaskPriorityStyle
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .font(AppFont.scaled(compact ? 9 : 10, weight: .bold))
            Text(style.label)
                .font(AppFont.scaled(compact ? 11 : 12, weight: .semibold))
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(style.color.opacity(0.14), in: Capsule())
    }
}

/// The neutral category pill (glyph + label) used in list rows.
struct CategoryPill: View {
    let style: TaskCategoryStyle

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .font(AppFont.scaled(10, weight: .semibold))
            Text(style.label)
                .font(AppFont.scaled(12, weight: .medium))
        }
        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
    }
}
