import SwiftUI

struct PropertySettingsView: View {
    @EnvironmentObject private var propertyService: PropertyService

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if let property = propertyService.primary {
                    propertyCard(property)
                    detailsSection(property)
                } else {
                    emptyState
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("My Property")
        .navigationBarTitleDisplayMode(.inline)
        .task { await propertyService.load() }
    }

    // MARK: - Property card

    private func propertyCard(_ p: PropertyModel) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                        Image(systemName: "house.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text("\(p.addressLine1), \(p.city)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(p.propertyType.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.blue.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                }

                if let score = p.healthScore {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.7))
                        Text("Health Score")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("\(score)/100")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: - Details

    private func detailsSection(_ p: PropertyModel) -> some View {
        SettingsGroup(title: "Details") {
            PropDetailRow(label: "Address", value: p.addressLine1)
            PropDetailRow(label: "City", value: p.city)
            PropDetailRow(label: "Country", value: p.country)
            if let sqm = p.sizeSqm {
                PropDetailRow(label: "Area", value: String(format: "%.0f m²", sqm))
            }
            if let rooms = p.numRooms {
                PropDetailRow(label: "Rooms", value: "\(rooms)")
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "house.circle")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.2))
            Text("No property found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text("Your property data will appear here once it's configured.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

private struct PropDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        Rectangle().fill(.white.opacity(0.05)).frame(height: 0.5).padding(.leading, 14)
    }
}
