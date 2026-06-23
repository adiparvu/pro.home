import SwiftUI

// MARK: - Receipt Detail

struct ReceiptDetailView: View {
    @EnvironmentObject private var receiptService: ReceiptService
    @EnvironmentObject private var propertyService: PropertyService
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
                .padding(.horizontal, 20).padding(.top, 16)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(receipt.categoryColor.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: receipt.categoryIcon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(receipt.categoryColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(receipt.storeName.isEmpty ? String(localized: "expense_unknown_store") : receipt.storeName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Text(receipt.formattedDate)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(ReceiptCategory.label(for: receipt.category))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(receipt.categoryColor)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(receipt.categoryColor.opacity(0.12), in: Capsule())
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(receipt.formattedTotal)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(String(localized: "receipt_total_label"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "receipt_items_section"))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if item.quantity != 1 {
                                        Text(String(format: "%.0f × %@", item.quantity, Receipt.format(item.unitPrice)))
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Receipt.format(item.totalPrice))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            if idx < items.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 14)
                            }
                        }
                    }

                    // Total row
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                    HStack {
                        Text(String(localized: "receipt_total_label"))
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                        Spacer()
                        Text(receipt.formattedTotal)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(.primary).monospacedDigit()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
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
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                GlassCard(padding: 14) {
                    Text(notes)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.7))
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
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 4)
    }
}
