import SwiftUI
import MapKit

extension DigitalTwinView {

    // MARK: - Layer Bar

    var layerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                layerChip(nil, label: "All", icon: "square.stack.3d.up.fill")
                ForEach(PropertyLayer.allCases, id: \.self) { layer in
                    layerChip(layer, label: layer.displayName, icon: layer.icon)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.clear)
    }

    private func layerChip(_ layer: PropertyLayer?, label: String, icon: String) -> some View {
        let active = activeLayer == layer
        return Button {
            withAnimation(.spring(response: 0.3)) { activeLayer = layer }
            HapticFeedback.selection()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(active ? .primary : Color.primary.opacity(0.65))
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassCapsule()
        .overlay {
            if active {
                Capsule().strokeBorder(Color.primary.opacity(0.35), lineWidth: 1.2)
            }
        }
    }

    // MARK: - Side Controls

    var sideControls: some View {
        VStack(spacing: 12) {
            controlButton(icon: isAerial ? "map.fill" : "airplane",
                          tint: isAerial ? .accentColor : .primary) {
                withAnimation(.spring(response: 0.4)) { isAerial.toggle() }
                HapticFeedback.selection()
            }
            controlButton(icon: "sparkles", tint: Color(red: 0.6, green: 0.35, blue: 0.95)) {
                showInsights = true
                HapticFeedback.impact(.light)
            }
            controlButton(icon: is3D ? "rotate.3d.fill" : "rotate.3d",
                          tint: is3D ? .accentColor : .primary) {
                toggle3D()
            }
            controlButton(icon: heatmap ? "flame.fill" : "flame",
                          tint: heatmap ? .orange : .primary) {
                withAnimation(.spring(response: 0.3)) { heatmap.toggle() }
            }
            controlButton(icon: showLabels ? "tag.fill" : "tag",
                          tint: showLabels ? .accentColor : .primary) {
                withAnimation(.spring(response: 0.3)) { showLabels.toggle() }
            }
            controlButton(icon: "heart.text.square.fill", tint: .pink) {
                showHealth = true
            }
            controlButton(icon: "cube.box.fill", tint: .primary) {
                showAddObject = true
                HapticFeedback.impact(.light)
            }
            controlButton(icon: "plus.viewfinder", tint: .primary) {
                startDrawing()
            }
            controlButton(icon: "scope", tint: .primary) {
                recenter()
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 36)
    }

    // MARK: - Heatmap Legend

    var heatmapLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HEALTH")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [.red, .orange, Color(red: 0.2, green: 0.8, blue: 0.45)],
                        startPoint: .bottom, endPoint: .top))
                    .frame(width: 8, height: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text("100").font(.system(size: 9, weight: .semibold))
                    Spacer()
                    Text("50").font(.system(size: 9, weight: .semibold))
                    Spacer()
                    Text("0").font(.system(size: 9, weight: .semibold))
                }
                .frame(height: 56)
                .foregroundStyle(.primary)
            }
        }
        .padding(10)
        .glassRoundedRect(14)
        .allowsHitTesting(false)
        .padding(.leading, 16)
        .padding(.bottom, 36)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .transition(.opacity)
    }

    private func controlButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .glassCircle()
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 3)
    }

    // MARK: - Draw Mode UI

    var drawBanner: some View {
        Text(draftPoints.count < 3
             ? "Tap the map to add corners (\(draftPoints.count)/3)"
             : "\(draftPoints.count) corners · tap to add more")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .allowsHitTesting(false)
            .padding(.top, 60)
            .shadow(color: Color.black.opacity(0.2), radius: 10, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    var drawToolbar: some View {
        HStack(spacing: 10) {
            drawButton("Cancel", icon: "xmark", tint: .red) { cancelDrawing() }
            drawButton("Undo", icon: "arrow.uturn.backward", tint: .primary) {
                if !draftPoints.isEmpty { draftPoints.removeLast() }
            }
            .disabled(draftPoints.isEmpty)
            drawButton("Save", icon: "checkmark", tint: .green) {
                Task { await saveDrawnZone() }
            }
            .disabled(draftPoints.count < 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCapsule()
        .padding(.bottom, 40)
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Object Drag UI

    var objectDragBanner: some View {
        let targetName = dragTargetZoneId.flatMap { id in zoneService.zones.first { $0.id == id }?.name }
        return HStack(spacing: 6) {
            Image(systemName: targetName != nil ? "arrow.down.to.line" : "mappin.slash")
                .font(.system(size: 12, weight: .bold))
            Text(targetName != nil ? "→ \(targetName!)" : "Outside zones")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(targetName != nil ? Color(red: 0.2, green: 0.75, blue: 0.4) : .secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassCapsule()
        .allowsHitTesting(false)
        .padding(.top, 60)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Reshape UI

    var reshapeBanner: some View {
        Text("Drag corners · double-tap to remove a corner")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .allowsHitTesting(false)
            .padding(.top, 60)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    var reshapeToolbar: some View {
        HStack(spacing: 10) {
            drawButton("Cancel", icon: "xmark", tint: .red) { cancelReshape() }
            drawButton("Save", icon: "checkmark", tint: .green) {
                Task { await saveReshape() }
            }
            .disabled(reshapePoints.count < 3)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCapsule()
        .padding(.bottom, 40)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func drawButton(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
