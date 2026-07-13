import SwiftUI
import CoreLocation

// MARK: - Shared background
//
// `appBackground` lives in Components/AppBackdrop.swift now — it became the
// living mood backdrop (AppBackdrop), not a flat color. Same name, same
// call sites; only the definition moved out of this feature file.

// MARK: - Home Widget Card
//
// Dashboard-only (the widgets strip under the smart-home grid): native
// Liquid Glass, so the whole page speaks the app's one language. Content
// and layout are untouched — icon + badge row, big value, subtitle, title —
// only the material changed: `liquidGlass` card, adaptive `.primary`/
// `.secondary` type over the mood backdrop, and the shared press
// micro-interaction. Semantic icon colors (danger red, success green,
// warning orange) are passed in unchanged by the callers.

struct HomeWidget: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let value: String
    let subtitle: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(AppFont.scaled(22, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 36, height: 36)
                    Spacer()
                    if badge > 0 {
                        Text("\(min(badge, 99))")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.xs).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(AppFont.scaled(22, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Inside the label so the glass scales WITH the pressed card.
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(SmartCardPressStyle())
    }
}

// MARK: - Property Section model

struct PropertySection: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let latOffset: Double
    let lonOffset: Double

    func offset(from coord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: coord.latitude + latOffset * 0.0003,
            longitude: coord.longitude + lonOffset * 0.0003
        )
    }

    static let all: [PropertySection] = [
        PropertySection(name: "House",      icon: "house.fill",       color: Color.brandSkyBlue,  latOffset:  1.2, lonOffset:  0.0),
        PropertySection(name: "Yard",      icon: "leaf.fill",        color: Color.brandSuccess, latOffset: -0.8, lonOffset:  0.9),
        PropertySection(name: "Garage",    icon: "car.fill",         color: Color(red: 0.9,  green: 0.65, blue: 0.2),  latOffset: -1.2, lonOffset: -0.5),
        PropertySection(name: "Garden",    icon: "tree.fill",        color: Color(red: 0.25, green: 0.75, blue: 0.35), latOffset:  0.5, lonOffset:  1.3),
        PropertySection(name: "Solar",     icon: "sun.max.fill",     color: Color(red: 1.0,  green: 0.85, blue: 0.2),  latOffset:  1.0, lonOffset: -1.2),
        PropertySection(name: "Gazebo",    icon: "umbrella.fill",    color: Color(red: 0.7,  green: 0.45, blue: 0.95), latOffset: -0.5, lonOffset:  1.5),
        PropertySection(name: "Pool",      icon: "drop.fill",        color: Color(red: 0.2,  green: 0.75, blue: 0.95), latOffset: -1.5, lonOffset:  0.8),
        PropertySection(name: "Utilities", icon: "bolt.fill",        color: Color(red: 1.0,  green: 0.55, blue: 0.2),  latOffset:  0.8, lonOffset: -1.5),
        PropertySection(name: "Projects",  icon: "hammer.fill",      color: Color.brandDanger, latOffset: -1.0, lonOffset: -1.3),
        PropertySection(name: "Documents", icon: "doc.fill",         color: Color(red: 0.55, green: 0.55, blue: 0.95), latOffset:  1.5, lonOffset:  0.6),
        PropertySection(name: "Inventory", icon: "shippingbox.fill", color: Color(red: 0.8,  green: 0.5,  blue: 0.3),  latOffset: -0.3, lonOffset: -1.8),
    ]
}

// MARK: - CategoryFilterChip (used across Zones, Objects screens)

struct CategoryFilterChip: View {
    let label: LocalizedStringKey
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: { HapticFeedback.selection(); action() }) {
            Text(label)
                .font(AppFont.scaled(13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .primary : Color.primary.opacity(0.55))
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.sm)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(isActive ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.primary.opacity(AppOpacity.hairline)))
                .overlay {
                    if isActive {
                        Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                }
        }
    }
}

// MARK: - Proactive Insights Strip

struct ProactiveInsightsStrip: View {
    var engine: ProactiveEngine

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(Color.brandPurple)
                    Text("Property Insights")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer()
                    Text("\(engine.activeInsights.count)")
                        .font(AppFont.scaled(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.brandPurple, in: Capsule())
                }
                ForEach(engine.activeInsights.prefix(3)) { insight in
                    InsightRow(insight: insight) {
                        engine.dismiss(insight)
                    }
                }
            }
        }
    }
}

private struct InsightRow: View {
    let insight: ProactiveInsight
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.category.icon)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(categoryColor)
                .frame(width: 28, height: 28)
                .background(categoryColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                Text(insight.body)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineLimit(2)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(AppFont.scaled(10, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            .accessibilityLabel("Dismiss")
        }
    }

    private var categoryColor: Color {
        switch insight.category {
        case .warranty:    return .orange
        case .maintenance: return .blue
        case .seasonal:    return .teal
        case .financial:   return .green
        case .age:         return .red
        }
    }
}
