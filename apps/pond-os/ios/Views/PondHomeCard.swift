import SwiftUI

// MARK: - PondHomeCard
//
// Compact card for PropertyHomeView's bottom panel / stats strip.
// Shows pond count + top-level health summary. Navigates to PondEntryView.
// Drop-in: add to PropertyHomeView only when ponds.count > 0.

struct PondHomeCard: View {
    let ponds: [Pond]
    let healthSnapshots: [UUID: PondHealthSnapshot]
    var onTap: () -> Void

    private var overallScore: Int {
        guard !ponds.isEmpty else { return 0 }
        let scores = ponds.compactMap { healthSnapshots[$0.id]?.overallScore }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / scores.count
    }

    private var scoreColor: Color {
        switch overallScore {
        case 80...100: return Color(hex: "#30D158")
        case 60..<80:  return Color(hex: "#FFD60A")
        case 40..<60:  return Color(hex: "#FF9F0A")
        default:       return Color(hex: "#FF3B30")
        }
    }

    private var criticalCount: Int {
        healthSnapshots.values.flatMap { _ in [] as [PondAlert] }.count
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "#0A84FF").opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: "water.waves")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: "#0A84FF"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(ponds.count == 1 ? ponds[0].name : "\(ponds.count) Ponds")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if !healthSnapshots.isEmpty {
                            Circle()
                                .fill(scoreColor)
                                .frame(width: 6, height: 6)
                            Text("Health \(overallScore)%")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        } else {
                            Text("Tap to manage")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                }

                Spacer()

                // Health mini-orb
                if !healthSnapshots.isEmpty {
                    ZStack {
                        Circle()
                            .fill(scoreColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Text("\(overallScore)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(scoreColor)
                    }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#0A84FF").opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color(hex: "#0A84FF").opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: overallScore)
    }
}

// MARK: - PondEntryView
//
// Top-level Pond OS coordinator.
// Empty state with AddPondSheet prompt, or PondDashboardView for single pond,
// or pond list for multi-pond properties.

struct PondEntryView: View {
    let propertyId: String
    @StateObject private var pondService = PondService()
    @State private var showAddPond = false
    @State private var selectedPond: Pond?

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            if pondService.isLoading {
                ProgressView()
                    .tint(.white)
            } else if pondService.ponds.isEmpty {
                emptyState
            } else if pondService.ponds.count == 1, let pond = pondService.ponds.first {
                PondDashboardView(pond: pond)
            } else {
                pondListView
            }
        }
        .navigationTitle("Pond OS")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddPond = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showAddPond) {
            AddPondSheet(propertyId: propertyId, pondService: pondService) { newPond in
                selectedPond = newPond
            }
        }
        .navigationDestination(item: $selectedPond) { pond in
            PondDashboardView(pond: pond)
        }
        .task {
            try? await pondService.load(for: propertyId)
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(hex: "#0A84FF").opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "water.waves")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(hex: "#0A84FF").opacity(0.6))
            }

            VStack(spacing: 8) {
                Text("No ponds yet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("Create your first pond to start monitoring water quality, managing fish, and automating feeding schedules.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                showAddPond = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Pond")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color(hex: "#0A84FF"))
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: Pond List (multi-pond)

    private var pondListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(pondService.ponds) { pond in
                    PondListRow(pond: pond)
                        .onTapGesture { selectedPond = pond }
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - PondListRow

private struct PondListRow: View {
    let pond: Pond

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#0A84FF").opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: pond.type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "#0A84FF"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(pond.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Text(pond.type.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))

                    if let vol = pond.volumeLiters {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.2))
                        Text(String(format: "%.0f L", vol))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}
