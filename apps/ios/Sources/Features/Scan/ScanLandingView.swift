import SwiftUI

// MARK: - Scan landing (IMG_8718)
//
// The dedicated page a scanned QR label opens — reachable ONLY through a
// scan (universal link https://xparvu.com/i|p/<uuid>, the prvio:// scheme
// fallbacks, or the in-app scanner). One glance answers "what did I just
// scan?": the thing's face, its live status, and the two actions that
// matter — jump to the full page, or dismiss and move on. Fetches by id
// straight from the server so it works even before the module's list has
// loaded (cold launch from the camera).

struct ScanLandingView: View {
    let target: AppRouter.ScanTarget

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private enum Loaded {
        case loading
        case item(InventoryItem)
        case plant(Plant)
        case missing
    }
    @State private var state: Loaded = .loading

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                content
            }
            .navigationTitle("scan_landing_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.primary)
                }
            }
        }
        .sheetGround()
        .presentationDetents([.medium, .large])
        .task(id: target.id) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView().controlSize(.large)
        case .missing:
            // Honest empty state: the label exists, the record doesn't
            // (deleted item / other property / no access).
            VStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(AppFont.scaled(44))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                Text("scan_landing_missing")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(AppSpacing.xl)
        case .item(let item):
            itemCard(item)
        case .plant(let plant):
            plantCard(plant)
        }
    }

    // MARK: Item

    private func itemCard(_ item: InventoryItem) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                heroFace(photo: InventoryImageStore.load(for: item.id),
                         icon: item.categoryIcon, tint: item.categoryColor)
                Text(item.name)
                    .font(AppFont.scaled(24, weight: .bold))
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    chip(InventoryLabels.category(item.category), icon: item.categoryIcon)
                    if !item.location.isEmpty {
                        chip(InventoryLabels.location(item.location), icon: "mappin.circle.fill")
                    }
                }
                if let loan = item.currentLoan {
                    statusRow(icon: "person.fill.turn.right", tint: .orange,
                              text: String(format: String(localized: "scan_landing_loaned_fmt"),
                                           loan.borrowerName))
                } else {
                    statusRow(icon: "checkmark.circle.fill", tint: Color.brandSuccess,
                              text: String(localized: "scan_landing_home"))
                }
                openFullButton {
                    router.pendingInventoryItemId = item.id
                    router.navigate(to: .inventory)
                }
            }
            .padding(AppSpacing.xl)
        }
    }

    // MARK: Plant

    private func plantCard(_ plant: Plant) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                heroFace(photo: nil, emoji: plant.emoji, tint: plant.healthColor)
                Text(plant.nickname?.isEmpty == false ? plant.nickname! : plant.name)
                    .font(AppFont.scaled(24, weight: .bold))
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    if let species = plant.species, !species.isEmpty {
                        chip(species, icon: "leaf.fill")
                    }
                    if let location = plant.location, !location.isEmpty {
                        chip(location, icon: "mappin.circle.fill")
                    }
                }
                statusRow(icon: plant.healthIcon, tint: plant.healthColor,
                          text: plant.wateringLabel)
                if let since = ISODate.date(from: plant.createdAt) {
                    statusRow(icon: "calendar", tint: Color.brandSkyBlue,
                              text: String(format: String(localized: "scan_landing_since_fmt"),
                                           AppDate.monthDayYear.string(from: since)))
                }
                openFullButton {
                    router.navigate(to: .plants(id: plant.id))
                }
            }
            .padding(AppSpacing.xl)
        }
    }

    // MARK: Shared pieces

    @ViewBuilder
    private func heroFace(photo: UIImage?, icon: String? = nil,
                          emoji: String? = nil, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 110, height: 110)
            if let photo {
                Image(uiImage: photo)
                    .resizable().scaledToFill()
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
            } else if let emoji {
                Text(emoji).font(AppFont.scaled(52))
            } else if let icon {
                Image(systemName: icon)
                    .font(AppFont.scaled(42))
                    .foregroundStyle(tint)
            }
        }
        .padding(.top, AppSpacing.sm)
    }

    private func chip(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(AppFont.scaled(11))
            Text(text).font(AppFont.scaled(12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func statusRow(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text)
                .font(AppFont.scaled(14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            Spacer()
        }
        .padding(AppSpacing.base)
        .background(Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    private func openFullButton(action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.medium)
            action()
        } label: {
            Label("scan_landing_open_full", systemImage: "arrow.up.right.square.fill")
                .font(AppFont.scaled(15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, AppSpacing.xs)
    }

    // MARK: Data

    private func load() async {
        state = .loading
        switch target {
        case .item(let id):
            if let record: DBInventoryRecord = try? await supabase
                .from("inventory_items").select()
                .eq("id", value: id.uuidString)
                .single().execute().value {
                state = .item(record.toInventoryItem())
            } else {
                state = .missing
            }
        case .plant(let id):
            if let plant: Plant = try? await supabase
                .from("plants").select()
                .eq("id", value: id.uuidString)
                .single().execute().value {
                state = .plant(plant)
            } else {
                state = .missing
            }
        }
    }
}
