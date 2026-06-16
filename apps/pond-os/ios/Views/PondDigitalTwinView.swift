import SwiftUI

// MARK: - PondDigitalTwinView
//
// Top-down 2D interactive pond visualization.
// Self-contained SwiftUI Canvas — does NOT modify or inherit from TwinCanvas.
// Shows zones, equipment, live sensor values at their mapped positions.

struct PondDigitalTwinView: View {
    let pond: Pond
    let zones: [PondZone]
    let equipment: [PondEquipment]
    let latestReadings: [WaterParameter: WaterQualityReading]

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var selectedZone: PondZone? = nil
    @State private var selectedEquipment: PondEquipment? = nil
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    // Pond canvas
                    PondCanvasView(
                        bounds: geo.size,
                        pond: pond,
                        zones: zones,
                        equipment: equipment,
                        latestReadings: latestReadings,
                        scale: scale * magnifyBy,
                        offset: CGSize(
                            width: offset.width + dragOffset.width,
                            height: offset.height + dragOffset.height
                        ),
                        selectedZoneId: selectedZone?.id,
                        onZoneTap: { zone in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedZone = selectedZone?.id == zone.id ? nil : zone
                                selectedEquipment = nil
                            }
                        },
                        onEquipmentTap: { item in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedEquipment = selectedEquipment?.id == item.id ? nil : item
                                selectedZone = nil
                            }
                        }
                    )
                    .gesture(dragGesture)
                    .gesture(magnifyGesture.simultaneously(with: dragGesture))

                    // Detail panel (bottom)
                    VStack {
                        Spacer()
                        if let zone = selectedZone {
                            PondZoneDetailPanel(zone: zone, readings: latestReadings)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if let item = selectedEquipment {
                            PondEquipmentDetailPanel(equipment: item)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }

            // Controls overlay
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        zoomButton(icon: "plus", action: { withAnimation { scale = min(scale * 1.3, 4.0) } })
                        zoomButton(icon: "minus", action: { withAnimation { scale = max(scale / 1.3, 0.5) } })
                        zoomButton(icon: "arrow.counterclockwise", action: { withAnimation { scale = 1.0; offset = .zero } })
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
        .navigationTitle("Pond Twin")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                dragOffset = .zero
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnifyBy) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                scale = max(0.5, min(4.0, scale * value.magnification))
            }
    }

    private func zoomButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
        }
        .glassCircle()
    }
}

// MARK: - PondCanvasView

private struct PondCanvasView: View {
    let bounds: CGSize
    let pond: Pond
    let zones: [PondZone]
    let equipment: [PondEquipment]
    let latestReadings: [WaterParameter: WaterQualityReading]
    let scale: CGFloat
    let offset: CGSize
    let selectedZoneId: UUID?
    let onZoneTap: (PondZone) -> Void
    let onEquipmentTap: (PondEquipment) -> Void

    private var center: CGPoint { CGPoint(x: bounds.width / 2 + offset.width,
                                          y: bounds.height / 2 + offset.height) }
    private var pondWidth: CGFloat  { min(bounds.width, bounds.height) * 0.65 * scale }
    private var pondHeight: CGFloat { pondWidth * 0.65 }

    var body: some View {
        ZStack {
            // Background grid
            Canvas { context, size in
                let gridSize: CGFloat = 40 * scale
                let cols = Int(size.width / gridSize) + 2
                let rows = Int(size.height / gridSize) + 2
                let startX = offset.width.truncatingRemainder(dividingBy: gridSize)
                let startY = offset.height.truncatingRemainder(dividingBy: gridSize)
                var path = Path()
                for col in 0...cols {
                    let x = startX + CGFloat(col) * gridSize
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for row in 0...rows {
                    let y = startY + CGFloat(row) * gridSize
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 0.5)
            }

            // Pond water body
            PondWaterBody(center: center, width: pondWidth, height: pondHeight)

            // Zone overlays
            ForEach(zones) { zone in
                PondZoneOverlay(
                    zone: zone,
                    center: center,
                    pondWidth: pondWidth,
                    pondHeight: pondHeight,
                    isSelected: selectedZoneId == zone.id
                )
                .onTapGesture { onZoneTap(zone) }
            }

            // Equipment markers
            ForEach(equipment) { item in
                PondEquipmentMarker(
                    equipment: item,
                    center: center,
                    pondWidth: pondWidth,
                    pondHeight: pondHeight
                )
                .onTapGesture { onEquipmentTap(item) }
            }

            // Sensor value labels (primary params only)
            sensorLabels
        }
    }

    @ViewBuilder
    private var sensorLabels: some View {
        // Temperature — top center
        if let temp = latestReadings[.temperature]?.value {
            sensorLabel(
                value: String(format: "%.1f°C", temp),
                icon: "thermometer.medium",
                color: Color(hex: "#FF6B35"),
                position: CGPoint(x: center.x, y: center.y - pondHeight / 2 - 24)
            )
        }
        // pH — left
        if let ph = latestReadings[.ph]?.value {
            sensorLabel(
                value: String(format: "pH %.1f", ph),
                icon: "atom",
                color: Color(hex: "#BF5AF2"),
                position: CGPoint(x: center.x - pondWidth / 2 - 30, y: center.y)
            )
        }
        // DO — right
        if let doVal = latestReadings[.dissolvedOxygen]?.value {
            sensorLabel(
                value: String(format: "%.1f mg/L", doVal),
                icon: "bubbles.and.sparkles",
                color: Color(hex: "#34C759"),
                position: CGPoint(x: center.x + pondWidth / 2 + 30, y: center.y)
            )
        }
    }

    private func sensorLabel(value: String, icon: String, color: Color, position: CGPoint) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5))
        )
        .position(position)
    }
}

// MARK: - Pond Water Body

private struct PondWaterBody: View {
    let center: CGPoint
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "#0A3D6B").opacity(0.9),
                        Color(hex: "#051B3A").opacity(0.95)
                    ],
                    center: .init(x: 0.4, y: 0.35),
                    startRadius: 0,
                    endRadius: width * 0.5
                )
            )
            .overlay(
                Ellipse()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color(hex: "#1E88E5").opacity(0.5), Color(hex: "#0A84FF").opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .overlay(
                // Water shimmer
                Ellipse()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: width * 0.5, height: height * 0.3)
                    .offset(x: -width * 0.1, y: -height * 0.15)
                    .blendMode(.plusLighter)
            )
            .frame(width: width, height: height)
            .shadow(color: Color(hex: "#0A84FF").opacity(0.2), radius: 20)
            .position(center)
    }
}

// MARK: - Pond Zone Overlay

private struct PondZoneOverlay: View {
    let zone: PondZone
    let center: CGPoint
    let pondWidth: CGFloat
    let pondHeight: CGFloat
    let isSelected: Bool

    private var pos: CGPoint {
        CGPoint(
            x: center.x + (zone.positionX - 0.5) * pondWidth,
            y: center.y + (zone.positionY - 0.5) * pondHeight
        )
    }

    private var radius: CGFloat { pondWidth * zone.radiusPercent }
    private var zoneColor: Color { Color(hex: zone.colorHex) }

    var body: some View {
        ZStack {
            Circle()
                .fill(zoneColor.opacity(isSelected ? 0.25 : 0.12))
                .overlay(
                    Circle()
                        .strokeBorder(zoneColor.opacity(isSelected ? 0.7 : 0.3),
                                      lineWidth: isSelected ? 1.5 : 0.5)
                )
                .scaleEffect(isSelected ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

            VStack(spacing: 3) {
                Image(systemName: zone.zoneType.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(zoneColor)
                Text(zone.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: radius * 2, height: radius * 2)
        .position(pos)
    }
}

// MARK: - Pond Equipment Marker

private struct PondEquipmentMarker: View {
    let equipment: PondEquipment
    let center: CGPoint
    let pondWidth: CGFloat
    let pondHeight: CGFloat

    private var pos: CGPoint {
        CGPoint(
            x: center.x + (equipment.positionX - 0.5) * pondWidth,
            y: center.y + (equipment.positionY - 0.5) * pondHeight
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(equipment.isRunning
                      ? Color(hex: "#34C759").opacity(0.2)
                      : Color.white.opacity(0.08))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .strokeBorder(equipment.isRunning
                                      ? Color(hex: "#34C759").opacity(0.5)
                                      : Color.white.opacity(0.15),
                                      lineWidth: 0.5)
                )

            Image(systemName: equipment.type.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(equipment.isRunning ? Color(hex: "#34C759") : .white.opacity(0.4))
        }
        .shadow(color: equipment.isRunning ? Color(hex: "#34C759").opacity(0.4) : .clear, radius: 6)
        .position(pos)
    }
}

// MARK: - Detail Panels

private struct PondZoneDetailPanel: View {
    let zone: PondZone
    let readings: [WaterParameter: WaterQualityReading]

    var body: some View {
        HeavyGlassCard(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: zone.colorHex).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: zone.zoneType.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(hex: zone.colorHex))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(zone.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(zone.zoneType.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                if let temp = readings[.temperature]?.value {
                    VStack(spacing: 2) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#FF6B35"))
                        Text(String(format: "%.1f°", temp))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

private struct PondEquipmentDetailPanel: View {
    let equipment: PondEquipment

    var body: some View {
        HeavyGlassCard(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(equipment.isRunning
                              ? Color(hex: "#34C759").opacity(0.15)
                              : Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: equipment.type.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(equipment.isRunning ? Color(hex: "#34C759") : .white.opacity(0.5))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(equipment.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text(equipment.type.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        if let brand = equipment.brand {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.2))
                            Text(brand)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }

                Spacer()

                Text(equipment.isRunning ? "Running" : "Off")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(equipment.isRunning ? Color(hex: "#34C759") : .white.opacity(0.35))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(equipment.isRunning
                                  ? Color(hex: "#34C759").opacity(0.12)
                                  : Color.white.opacity(0.06))
                    )
            }
        }
    }
}
