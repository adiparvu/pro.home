import SwiftUI

// MARK: - Receipt Detail

struct ReceiptDetailView: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    let receipt: Receipt
    @State private var showDeleteConfirm = false

    private var items: [ReceiptItem] { receiptService.items(for: receipt.id) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroCard
                    if !items.isEmpty { itemsSection }
                    notesSection
                    deleteButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(receipt.storeName.isEmpty ? String(localized: "expense_unknown_store") : receipt.storeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(String(localized: "receipt_delete_confirm"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(String(localized: "Delete"), role: .destructive) {
                    Task { await receiptService.deleteReceipt(receipt) }
                    dismiss()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        GlassCard(padding: 20) {
            HStack(spacing: 16) {
                Image(systemName: receipt.categoryIcon)
                    .font(AppFont.scaled(26, weight: .semibold))
                    .foregroundStyle(receipt.categoryColor)
                    .frame(width: 60, height: 60)
                    .glassRoundedRect(AppRadius.lg)

                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.storeName.isEmpty ? String(localized: "expense_unknown_store") : receipt.storeName)
                        .font(AppFont.scaled(18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Text(receipt.formattedDate)
                            .font(AppFont.scaled(13))
                            .foregroundStyle(.secondary)
                        Text(ReceiptCategory.label(for: receipt.category))
                            .font(AppFont.caption)
                            .foregroundStyle(receipt.categoryColor)
                            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                            .background(receipt.categoryColor.opacity(0.12), in: Capsule())
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(receipt.formattedTotal)
                        .font(AppFont.title2)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(String(localized: "receipt_total_label"))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "receipt_items_section"))
                .font(AppFont.captionStrong).foregroundStyle(.secondary).padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(AppFont.footnote)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if item.quantity != 1 {
                                        Text(String(format: "%.0f × %@", item.quantity, Receipt.format(item.unitPrice)))
                                            .font(AppFont.scaled(11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Receipt.format(item.totalPrice))
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
                            if idx < items.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, AppSpacing.base)
                            }
                        }
                    }

                    // Total row
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    HStack {
                        Text(String(localized: "receipt_total_label"))
                            .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                        Spacer()
                        Text(receipt.formattedTotal)
                            .font(AppFont.scaled(15, weight: .bold)).foregroundStyle(.primary).monospacedDigit()
                    }
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
                }
            }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        if let notes = receipt.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOTES")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary).padding(.leading, AppSpacing.xxs)
                GlassCard(padding: 14) {
                    Text(notes)
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label(String(localized: "receipt_delete"), systemImage: "trash")
                .font(AppFont.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.base)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, AppSpacing.xxs)
    }
}
