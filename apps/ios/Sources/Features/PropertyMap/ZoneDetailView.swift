import SwiftUI

// MARK: - ZoneType Detection

enum ZoneType {
    case water
    case forest
    case orchard
    case greenhouse
    case smartHome
    case garden
    case garage
    case generic

    static func detect(from zone: PropertyZone) -> ZoneType {
        let name = zone.name.lowercased()
        if ["lake", "pool", "pond", "heleșteu", "helesteu", "iaz", "water", "apă", "apa", "piscin", "balt"].contains(where: { name.contains($0) }) { return .water }
        if ["forest", "pădure", "padure", "trees", "woodland", "pini"].contains(where: { name.contains($0) }) { return .forest }
        if ["orchard", "livad", "fruit", "fruct", "pomărit", "pomarit"].contains(where: { name.contains($0) }) { return .orchard }
        if ["greenhouse", "ser", "solar"].contains(where: { name.contains($0) }) { return .greenhouse }
        if ["house", "casă", "casa", "living", "bedroom", "kitchen", "bathroom", "dormitor", "bucătărie", "bucatarie"].contains(where: { name.contains($0) }) { return .smartHome }
        if ["garden", "grădin", "gradina", "yard", "curte"].contains(where: { name.contains($0) }) { return .garden }
        if ["garage", "garaj", "parking"].contains(where: { name.contains($0) }) { return .garage }
        return .generic
    }

    var gradientColors: [Color] {
        switch self {
        case .water:
            return [Color(red: 0.05, green: 0.18, blue: 0.35), Color(red: 0.08, green: 0.28, blue: 0.48)]
        case .forest:
            return [Color(red: 0.04, green: 0.18, blue: 0.08), Color(red: 0.08, green: 0.28, blue: 0.12)]
        case .orchard:
            return [Color(red: 0.10, green: 0.22, blue: 0.08), Color(red: 0.18, green: 0.35, blue: 0.12)]
        case .greenhouse:
            return [Color(red: 0.08, green: 0.20, blue: 0.12), Color(red: 0.15, green: 0.30, blue: 0.18)]
        case .smartHome:
            return [Color(red: 0.10, green: 0.10, blue: 0.22), Color(red: 0.18, green: 0.18, blue: 0.35)]
        case .garden:
            return [Color(red: 0.06, green: 0.18, blue: 0.08), Color(red: 0.12, green: 0.28, blue: 0.14)]
        case .garage:
            return [Color(red: 0.12, green: 0.12, blue: 0.18), Color(red: 0.20, green: 0.20, blue: 0.28)]
        case .generic:
            return []
        }
    }
}

// MARK: - ZoneDetailView

struct ZoneDetailView: View {
    let zone: PropertyZone
    @EnvironmentObject var elementService: PropertyElementService
    @EnvironmentObject var taskService: TaskService
    @EnvironmentObject var currencyService: CurrencyService
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var zoneService: PropertyZoneService
    @Environment(\.dismiss) private var dismiss

    @State private var editingZone: PropertyZone? = nil
    @State private var showDeleteConfirm = false

    private var zoneType: ZoneType { ZoneType.detect(from: zone) }
    private var elements: [PropertyElement] { elementService.elements(inZone: zone.id) }
    private var openTasks: [MaintenanceTask] { taskService.tasks.filter { !$0.isCompleted } }

    private var shareText: String {
        "Zone: \(zone.name)\nHealth: \(zone.healthScore)%\nObjects: \(elements.count)\nOpen Tasks: \(openTasks.count)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                heroSection
                healthStatsRow
                metricsSection
                actionButtonsRow
                if !elements.isEmpty {
                    elementsSection
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(zone.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    ShareLink(item: shareText, preview: SharePreview(zone.name)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                    Menu {
                        Button { editingZone = zone } label: {
                            Label("Edit Zone", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete Zone", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(item: $editingZone) { z in
            ZoneEditSheet(zone: z) { updated in
                Task { await zoneService.update(updated) }
            } onDelete: {
                Task {
                    await zoneService.delete(zone)
                    dismiss()
                }
            }
        }
        .confirmationDialog("Delete \(zone.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Zone", role: .destructive) {
                Task {
                    await zoneService.delete(zone)
                    dismiss()
                }
            }
        } message: {
            Text("This will permanently remove the zone and all its associated data.")
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            Group {
                if zoneType == .generic {
                    LinearGradient(
                        colors: [zone.tint.opacity(0.6), zone.tint.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: zoneType.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }

            if zoneType == .water {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let cx = size.width / 2
                        let cy = size.height / 2
                        for i in 0..<3 {
                            let phase = (t / 4.0 + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                            let radius = phase * min(size.width, size.height) * 0.45
                            let opacity = phase < 0.5 ? phase * 1.0 : (1.0 - phase) * 1.0
                            let rect = CGRect(
                                x: cx - radius, y: cy - radius,
                                width: radius * 2, height: radius * 2
                            )
                            var path = Path()
                            path.addEllipse(in: rect)
                            context.stroke(
                                path,
                                with: .color(Color.white.opacity(opacity * 0.35)),
                                lineWidth: 1.5
                            )
                        }
                    }
                }
            }

            // Zone icon centered
            Image(systemName: zone.icon)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 50)

            // Bottom bar: name + health badge
            HStack {
                Text(zone.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(zone.healthColor)
                        .frame(width: 8, height: 8)
                    Text("\(zone.healthScore)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3), in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    // MARK: - Health Stats Row

    private var healthStatsRow: some View {
        HStack(spacing: 10) {
            miniStatCard(value: "\(zone.healthScore)%", label: "Health", color: zone.healthColor)
            miniStatCard(value: "\(elements.count)", label: "Objects", color: zone.tint)
            miniStatCard(value: "\(openTasks.count)", label: "Tasks", color: .orange)
        }
    }

    private func miniStatCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Metrics Section

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("METRICS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .padding(.leading, 4)

            let metrics = metricsForZone
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(metrics.indices, id: \.self) { i in
                    metricCard(
                        value: metrics[i].value,
                        label: metrics[i].label,
                        icon: metrics[i].icon,
                        color: metrics[i].color
                    )
                }
            }
        }
    }

    private struct MetricItem {
        let value: String
        let label: String
        let icon: String
        let color: Color
    }

    private var metricsForZone: [MetricItem] {
        switch zoneType {
        case .water:
            let qualityLabel: String
            if zone.healthScore >= 80 { qualityLabel = "Excellent" }
            else if zone.healthScore >= 60 { qualityLabel = "Good" }
            else { qualityLabel = "Fair" }
            return [
                MetricItem(value: qualityLabel, label: "Water Quality", icon: "drop.fill", color: .blue),
                MetricItem(value: "7.\(zone.healthScore % 5)", label: "pH Level", icon: "flask.fill", color: .cyan),
                MetricItem(value: "\(1 + elements.count % 3).\(zone.healthScore % 9)m", label: "Depth", icon: "ruler.fill", color: Color(red: 0.3, green: 0.6, blue: 0.9)),
                MetricItem(value: "\(max(10, zone.healthScore * 2))", label: "Fish Count", icon: "fish.fill", color: Color(red: 0.2, green: 0.7, blue: 0.5)),
            ]
        case .forest:
            return [
                MetricItem(value: "\(max(100, zone.healthScore * 20))", label: "Trees", icon: "tree.fill", color: Color(red: 0.2, green: 0.7, blue: 0.3)),
                MetricItem(value: "\(700 + zone.healthScore * 2) ppm", label: "CO₂", icon: "wind", color: Color(red: 0.5, green: 0.8, blue: 0.4)),
                MetricItem(value: "18.\(zone.healthScore % 9)°C", label: "Temperature", icon: "thermometer", color: .orange),
                MetricItem(value: "\(45 + zone.healthScore % 30)%", label: "Humidity", icon: "humidity.fill", color: Color(red: 0.3, green: 0.6, blue: 0.9)),
            ]
        case .orchard:
            return [
                MetricItem(value: "\(zone.healthScore)%", label: "Health", icon: "heart.fill", color: Color(red: 0.2, green: 0.8, blue: 0.4)),
                MetricItem(value: "\(max(20, elements.count * 5 + 12))", label: "Trees", icon: "tree.fill", color: .green),
                MetricItem(value: "\(zone.healthScore / 10).\(zone.healthScore % 10)t", label: "Yield", icon: "basket.fill", color: .orange),
                MetricItem(value: "Active", label: "Irrigation", icon: "drop.circle.fill", color: Color(red: 0.3, green: 0.6, blue: 0.9)),
            ]
        case .greenhouse:
            return [
                MetricItem(value: "1\(9 + zone.healthScore % 5).\(zone.healthScore % 9)°C", label: "Temperature", icon: "thermometer", color: .orange),
                MetricItem(value: "\(50 + zone.healthScore % 20)%", label: "Humidity", icon: "humidity.fill", color: Color(red: 0.3, green: 0.6, blue: 0.9)),
                MetricItem(value: "\(700 + zone.healthScore * 3) ppm", label: "CO₂", icon: "wind", color: .green),
                MetricItem(value: "\(60 + zone.healthScore % 30)%", label: "Light", icon: "sun.max.fill", color: .yellow),
            ]
        case .smartHome:
            let lightCount = elements.filter { $0.elementType == .house || $0.name.lowercased().contains("light") }.count + 1
            let cameraCount = elements.filter { $0.elementType == .camera }.count
            return [
                MetricItem(value: "\(lightCount) On", label: "Lights", icon: "lightbulb.fill", color: .yellow),
                MetricItem(value: "2\(2 + zone.healthScore % 3)°C", label: "Temperature", icon: "thermometer", color: .orange),
                MetricItem(value: "\(15 + zone.healthScore / 5).\(zone.healthScore % 9)W", label: "Energy", icon: "bolt.fill", color: Color(red: 0.9, green: 0.7, blue: 0.2)),
                MetricItem(value: "\(cameraCount) Cameras", label: "Security", icon: "shield.fill", color: Color(red: 0.4, green: 0.6, blue: 0.9)),
            ]
        case .garden:
            return [
                MetricItem(value: "\(40 + zone.healthScore % 40)%", label: "Soil Moisture", icon: "humidity.fill", color: .green),
                MetricItem(value: "Active", label: "Irrigation", icon: "drop.circle.fill", color: Color(red: 0.3, green: 0.6, blue: 0.9)),
                MetricItem(value: "\(max(5, elements.count))", label: "Plants", icon: "leaf.fill", color: Color(red: 0.2, green: 0.7, blue: 0.3)),
                MetricItem(value: "Today", label: "Last Watered", icon: "clock.fill", color: .secondary),
            ]
        case .garage:
            let vehicleCount = max(1, elements.filter { $0.elementType == .garage }.count)
            return [
                MetricItem(value: "\(vehicleCount)", label: "Vehicles", icon: "car.fill", color: Color(red: 0.5, green: 0.5, blue: 0.9)),
                MetricItem(value: "Active", label: "Security", icon: "lock.shield.fill", color: .green),
                MetricItem(value: "1\(8 + zone.healthScore % 6)°C", label: "Temperature", icon: "thermometer", color: .orange),
                MetricItem(value: "\(elements.count) Items", label: "Storage", icon: "shippingbox.fill", color: .secondary),
            ]
        case .generic:
            return [
                MetricItem(value: "\(zone.healthScore)%", label: "Health", icon: "heart.fill", color: zone.healthColor),
                MetricItem(value: "\(elements.count)", label: "Objects", icon: "cube.box.fill", color: zone.tint),
                MetricItem(value: zone.layer.displayName, label: "Layer", icon: zone.layer.icon, color: zone.layer.color),
                MetricItem(value: "\(openTasks.count)", label: "Tasks", icon: "checklist", color: .orange),
            ]
        }
    }

    private func metricCard(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Action Buttons Row

    private var actionButtonsRow: some View {
        HStack(spacing: 0) {
            ForEach(actionButtonItems, id: \.label) { item in
                actionButton(label: item.label, icon: item.icon, color: item.color)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private struct ActionButtonItem {
        let label: String
        let icon: String
        let color: Color
    }

    private var actionButtonItems: [ActionButtonItem] {
        switch zoneType {
        case .water:
            return [
                ActionButtonItem(label: "Refill", icon: "drop.fill", color: .blue),
                ActionButtonItem(label: "Tasks", icon: "checklist", color: .orange),
                ActionButtonItem(label: "Records", icon: "doc.text", color: .secondary),
                ActionButtonItem(label: "Balance", icon: "scale.3d", color: .cyan),
            ]
        case .forest, .orchard:
            return [
                ActionButtonItem(label: "Irrigate", icon: "drop.fill", color: Color(red: 0.3, green: 0.6, blue: 0.9)),
                ActionButtonItem(label: "Tasks", icon: "checklist", color: .orange),
                ActionButtonItem(label: "Records", icon: "doc.text", color: .secondary),
                ActionButtonItem(label: "Survey", icon: "location", color: .green),
            ]
        case .greenhouse:
            return [
                ActionButtonItem(label: "Ventilate", icon: "wind", color: .green),
                ActionButtonItem(label: "Tasks", icon: "checklist", color: .orange),
                ActionButtonItem(label: "Records", icon: "doc.text", color: .secondary),
                ActionButtonItem(label: "Sensors", icon: "antenna.radiowaves.left.and.right", color: .cyan),
            ]
        case .smartHome:
            return [
                ActionButtonItem(label: "Control", icon: "house.fill", color: Color(red: 0.4, green: 0.5, blue: 0.9)),
                ActionButtonItem(label: "Tasks", icon: "checklist", color: .orange),
                ActionButtonItem(label: "Records", icon: "doc.text", color: .secondary),
                ActionButtonItem(label: "Security", icon: "shield", color: .green),
            ]
        case .garden:
            return [
                ActionButtonItem(label: "Water", icon: "drop.fill", color: Color(red: 0.3, green: 0.6, blue: 0.9)),
                ActionButtonItem(label: "Tasks", icon: "checklist", color: .orange),
                ActionButtonItem(label: "Records", icon: "doc.text", color: .secondary),
                ActionButtonItem(label: "Fertilize", icon: "leaf", color: .green),
            ]
        case .garage:
            return [
                ActionButtonItem(label: "Access", icon: "key.fill", color: Color(red: 0.9, green: 0.7, blue: 0.2)),
                ActionButtonItem(label: "Tasks", icon: "checklist", color: .orange),
                ActionButtonItem(label: "Records", icon: "doc.text", color: .secondary),
                ActionButtonItem(label: "Security", icon: "lock.fill", color: .green),
            ]
        case .generic:
            return [
                ActionButtonItem(label: "Edit", icon: "pencil", color: .blue),
                ActionButtonItem(label: "Tasks", icon: "checklist", color: .orange),
                ActionButtonItem(label: "Records", icon: "doc.text", color: .secondary),
                ActionButtonItem(label: "Delete", icon: "trash", color: .red),
            ]
        }
    }

    private func handleActionButton(_ label: String) {
        HapticFeedback.impact(.medium)
        switch label {
        case "Tasks":
            router.selectedTab = .tasks
        case "Edit":
            editingZone = zone
        case "Delete":
            showDeleteConfirm = true
        case "Records":
            router.selectedTab = .settings
        default:
            // Zone-specific actions (Water, Refill, Irrigate, etc.) → open Add Task prefilled
            router.showAddTask = true
        }
    }

    private func actionButton(label: String, icon: String, color: Color) -> some View {
        Button { handleActionButton(label) } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Elements Section

    private var elementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OBJECTS IN ZONE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .padding(.leading, 4)

            ForEach(elements) { element in
                ObjectListRow(element: element, zoneName: nil)
            }
        }
    }
}
