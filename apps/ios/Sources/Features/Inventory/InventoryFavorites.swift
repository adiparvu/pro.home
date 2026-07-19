import SwiftUI
import Observation

// MARK: - Favorites store
//
// Device-local favorites for inventory items, mirroring the ItemLockStore
// pattern: a UserDefaults-backed id set behind an observable singleton so
// every row/star updates instantly.

@MainActor
@Observable
final class InventoryFavorites {
    static let shared = InventoryFavorites()
    private static let key = "inventory.favorites"

    private(set) var ids: Set<UUID>

    private init() {
        let raw = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        ids = Set(raw.compactMap(UUID.init))
    }

    func isFavorite(_ id: UUID) -> Bool { ids.contains(id) }

    func toggle(_ id: UUID) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: Self.key)
    }
}

// MARK: - Long-press preview card

struct InventoryItemPreview: View {
    let item: InventoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let img = InventoryImageStore.avatar(for: item.id) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 320, height: 200)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(colors: [item.categoryColor.opacity(0.35),
                                            item.categoryColor.opacity(0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: item.categoryIcon)
                        .font(AppFont.scaled(56, weight: .medium))
                        .foregroundStyle(item.categoryColor)
                }
                .frame(width: 320, height: 160)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        if !item.brand.isEmpty {
                            Text(item.brand)
                            Text("·")
                        }
                        Text(verbatim: InventoryLabels.category(item.category))
                        Text("·")
                        Text(verbatim: InventoryLabels.location(item.location))
                    }
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.secondaryTextColor)
                }

                previewChip("checkmark.seal", Text(LocalizedStringKey(item.condition.capitalized)), .purple)

                // Discreet facts: what it's worth and how long the warranty
                // lives — the price/warranty chips grew into real rows.
                if item.purchasePrice > 0 || item.warrantyStatus != .none {
                    VStack(alignment: .leading, spacing: 5) {
                        if item.purchasePrice > 0 {
                            infoRow("eurosign.circle",
                                    Text(verbatim: CurrencyService.money(item.purchasePrice, code: "EUR", whole: true)),
                                    Color.primary.opacity(AppOpacity.mediumText))
                        }
                        switch item.warrantyStatus {
                        case .valid, .expiringSoon:
                            if let exp = item.warrantyExpiresAt {
                                infoRow(item.warrantyStatus == .expiringSoon ? "exclamationmark.shield" : "checkmark.shield",
                                        Text(String(format: String(localized: "inv_warranty_until"),
                                                    exp.formatted(date: .abbreviated, time: .omitted))),
                                        item.warrantyStatus == .expiringSoon ? .orange : Color.primary.opacity(AppOpacity.mediumText))
                            }
                        case .expired:
                            infoRow("xmark.shield", Text("inv_warranty_expired"), Color.brandDanger)
                        case .none:
                            EmptyView()
                        }
                    }
                }

                if let loan = item.currentLoan {
                    Label(String(format: String(localized: "Loaned to %@ · %dd"),
                                 loan.borrowerName, loan.daysOut),
                          systemImage: "person.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(.orange)
                }

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(3)
                }
            }
            .padding(AppSpacing.lg)
        }
        .frame(width: 320)
        .background(appBackground)
    }

    private func previewChip(_ icon: String, _ label: Text, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(AppFont.scaled(10, weight: .semibold))
            label
                .font(AppFont.label)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.13), in: Capsule())
    }

    private func infoRow(_ icon: String, _ label: Text, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.scaled(11, weight: .medium))
                .foregroundStyle(color)
            label
                .font(AppFont.scaled(12))
                .foregroundStyle(color)
        }
    }
}
