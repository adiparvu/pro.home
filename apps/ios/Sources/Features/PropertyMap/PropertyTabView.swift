import SwiftUI

// MARK: - Property Tab — Zones | Objects | Map segment picker

struct PropertyTabView: View {
    @EnvironmentObject var zoneService: PropertyZoneService
    @EnvironmentObject var elementService: PropertyElementService
    @EnvironmentObject var propertyService: PropertyService
    @EnvironmentObject var currencyService: CurrencyService
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var taskService: TaskService
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    enum Segment: String, CaseIterable {
        case zones   = "Zones"
        case objects = "Objects"
        case map     = "Map"

        var icon: String {
            switch self {
            case .zones:   return "square.stack.3d.up.fill"
            case .objects: return "cube.box.fill"
            case .map:     return "map.fill"
            }
        }
    }

    @State private var segment: Segment = .zones

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)

            Divider().opacity(0.10)

            switch segment {
            case .zones:
                ZonesListView()
            case .objects:
                ObjectsListView()
            case .map:
                DigitalTwinView()
            }
        }
        .background(appBackground.ignoresSafeArea())
    }

    // MARK: - Segment Picker

    private var segmentPicker: some View {
        HStack(spacing: 0) {
            ForEach(Segment.allCases, id: \.self) { seg in
                Button {
                    HapticFeedback.selection()
                    withAnimation(.spring(response: 0.3)) { segment = seg }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: seg.icon)
                            .font(AppFont.captionStrong)
                        Text(LocalizedStringKey(seg.rawValue))
                            .font(.system(size: 13, weight: segment == seg ? .semibold : .medium))
                    }
                    .foregroundStyle(segment == seg ? .primary : Color.primary.opacity(AppOpacity.secondaryText))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background {
                        if segment == seg {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.regularMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(AppOpacity.hairline))
        }
    }
}
