import SwiftUI
import CoreLocation

// MARK: - Shared background

var appBackground: Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.04, blue: 0.08, alpha: 1)
            : UIColor(red: 0.96, green: 0.96, blue: 0.985, alpha: 1)
    })
}

// MARK: - Home Widget Card

struct HomeWidget: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(iconColor.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    Spacer()
                    if badge > 0 {
                        Text("\(min(badge, 99))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .lineLimit(1)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 16)
    }
}

// MARK: - Property Core Marker

struct PropertyCoreMarker: View {
    @Binding var pulsing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(pulsing ? 0.08 : 0.22))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulsing ? 1.15 : 0.9)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulsing)

                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.45).opacity(pulsing ? 0.15 : 0.3))
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulsing ? 1.08 : 0.95)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true).delay(0.2), value: pulsing)

                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.25, green: 0.92, blue: 0.5), Color(red: 0.1, green: 0.75, blue: 0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 42, height: 42)
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.45).opacity(0.8), radius: 16)
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.45).opacity(0.4), radius: 30)

                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Property Point Marker

struct PropertyPointMarker: View {
    let section: PropertySection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(section.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                }
                Circle()
                    .fill(isSelected
                        ? LinearGradient(colors: [section.color, section.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(isSelected ? section.color : .white.opacity(0.3), lineWidth: 1.5))
                    .shadow(color: isSelected ? section.color.opacity(0.5) : .black.opacity(0.3), radius: isSelected ? 8 : 4)
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isSelected ? 1.15 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thumbnail Card

struct ThumbnailCard: View {
    let section: PropertySection
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected
                            ? LinearGradient(colors: [section.color, section.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isSelected ? section.color.opacity(0.5) : .white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: isSelected ? section.color.opacity(0.4) : .black.opacity(0.2), radius: isSelected ? 12 : 4)
                    Image(systemName: section.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                }
                Text(section.name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
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
        PropertySection(name: "House",      icon: "house.fill",       color: Color(red: 0.35, green: 0.65, blue: 1.0),  latOffset:  1.2, lonOffset:  0.0),
        PropertySection(name: "Yard",      icon: "leaf.fill",        color: Color(red: 0.3,  green: 0.85, blue: 0.45), latOffset: -0.8, lonOffset:  0.9),
        PropertySection(name: "Garage",    icon: "car.fill",         color: Color(red: 0.9,  green: 0.65, blue: 0.2),  latOffset: -1.2, lonOffset: -0.5),
        PropertySection(name: "Garden",    icon: "tree.fill",        color: Color(red: 0.25, green: 0.75, blue: 0.35), latOffset:  0.5, lonOffset:  1.3),
        PropertySection(name: "Solar",     icon: "sun.max.fill",     color: Color(red: 1.0,  green: 0.85, blue: 0.2),  latOffset:  1.0, lonOffset: -1.2),
        PropertySection(name: "Gazebo",    icon: "umbrella.fill",    color: Color(red: 0.7,  green: 0.45, blue: 0.95), latOffset: -0.5, lonOffset:  1.5),
        PropertySection(name: "Pool",      icon: "drop.fill",        color: Color(red: 0.2,  green: 0.75, blue: 0.95), latOffset: -1.5, lonOffset:  0.8),
        PropertySection(name: "Utilities", icon: "bolt.fill",        color: Color(red: 1.0,  green: 0.55, blue: 0.2),  latOffset:  0.8, lonOffset: -1.5),
        PropertySection(name: "Projects",  icon: "hammer.fill",      color: Color(red: 0.95, green: 0.35, blue: 0.35), latOffset: -1.0, lonOffset: -1.3),
        PropertySection(name: "Documents", icon: "doc.fill",         color: Color(red: 0.55, green: 0.55, blue: 0.95), latOffset:  1.5, lonOffset:  0.6),
        PropertySection(name: "Inventory", icon: "shippingbox.fill", color: Color(red: 0.8,  green: 0.5,  blue: 0.3),  latOffset: -0.3, lonOffset: -1.8),
    ]
}

// MARK: - Health Score Card

struct HealthScoreCard: View {
    let score: Int
    let isLoading: Bool

    private var color: Color {
        score >= 80 ? Color(red: 0.25, green: 0.88, blue: 0.55)
            : score >= 55 ? Color.orange
            : Color.red
    }
    private var label: String {
        score >= 80 ? "Excellent" : score >= 60 ? "Good" : score >= 40 ? "Fair" : "Needs Attention"
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: isLoading ? 0 : CGFloat(score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.1, dampingFraction: 0.8), value: score)
                    VStack(spacing: 1) {
                        Text(isLoading ? "–" : "\(score)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("/ 100")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Property Health")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(isLoading ? "Loading…" : label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color)
                    Text(isLoading ? " " : score >= 80
                         ? "Everything looks on track."
                         : "Some tasks need attention.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Stat Card

struct DashStatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Dash Task Row

struct DashTaskRow: View {
    let task: MaintenanceTask

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(task.priorityColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.primary.opacity(0.38) : Color.white)
                    .strikethrough(task.isCompleted, color: Color.primary.opacity(0.35))
                    .lineLimit(1)
                Text(task.dueDateDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(task.isOverdue ? .red.opacity(0.8) : Color.primary.opacity(0.38))
            }

            Spacer()

            Text(task.statusDisplay)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Finances Snapshot

struct FinancesSnapshotCard: View {
    let income: Double
    let expenses: Double
    let net: Double
    let symbol: String
    var isLoading: Bool = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Finances")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("This month")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                if isLoading {
                    HStack { Spacer(); ProgressView().tint(.white).scaleEffect(0.8); Spacer() }
                } else {
                    HStack(spacing: 0) {
                        FinStat(label: "Income", value: formatted(income), color: Color(red: 0.25, green: 0.88, blue: 0.55))
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 34)
                        FinStat(label: "Expenses", value: formatted(expenses), color: .orange)
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 34)
                        FinStat(label: "Net", value: formatted(net), color: net >= 0 ? .white : .red)
                    }
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "\(symbol)%.0f", value)
    }
}

private struct FinStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - PropertyHealthGauge (compact overlay for AerialPropertyView)

struct PropertyHealthGauge: View {
    let score: Int
    var size: CGFloat = 80

    private var scoreColor: Color {
        switch score {
        case 80...: return Color(red: 0.20, green: 0.87, blue: 0.48)
        case 55..<80: return .orange
        default: return .red
        }
    }

    private var label: String {
        switch score {
        case 80...: return "Good"
        case 55..<80: return "Fair"
        default: return "Poor"
        }
    }

    var body: some View {
        ZStack {
            // Background card
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: size * 0.075)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [scoreColor.opacity(0.7), scoreColor]),
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.0, dampingFraction: 0.8), value: score)

                    Text("\(score)")
                        .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: size * 0.62, height: size * 0.62)

                Text(label)
                    .font(.system(size: size * 0.115, weight: .semibold))
                    .foregroundStyle(scoreColor)
            }
            .padding(size * 0.10)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

// MARK: - StatChip (horizontal stats row)

struct StatChip: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .primary
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: action ?? {}) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(value)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 12)
        .allowsHitTesting(action != nil)
    }
}
