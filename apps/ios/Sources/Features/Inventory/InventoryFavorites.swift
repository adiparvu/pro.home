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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let img = InventoryImageStore.load(for: item.id) {
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
                        .font(.system(size: 56, weight: .medium))
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
                        Text(LocalizedStringKey(item.category.capitalized))
                        Text("·")
                        Text(LocalizedStringKey(item.location.capitalized))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryTextColor)
                }

                HStack(spacing: AppSpacing.sm) {
                    if item.purchasePrice > 0 {
                        previewChip("eurosign.circle.fill", Text(verbatim: CurrencyService.money(item.purchasePrice, code: "EUR", whole: true)), .blue)
                    }
                    previewChip("sparkles", Text(LocalizedStringKey(item.condition.capitalized)), .purple)
                    switch item.warrantyStatus {
                    case .valid:
                        previewChip("checkmark.shield.fill", Text("Warranty"), .green)
                    case .expiringSoon:
                        previewChip("exclamationmark.shield.fill", Text("Warranty"), .orange)
                    case .expired:
                        previewChip("xmark.shield.fill", Text("Expired"), .red)
                    case .none:
                        EmptyView()
                    }
                }

                if let loan = item.currentLoan {
                    Label(String(format: String(localized: "Loaned to %@ · %dd"),
                                 loan.borrowerName, loan.daysOut),
                          systemImage: "person.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                }

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.system(size: 13))
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
                .font(.system(size: 10, weight: .semibold))
            label
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.13), in: Capsule())
    }
}
