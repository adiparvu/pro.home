import SwiftUI

// MARK: - ApplianceDetailSheet

struct ApplianceDetailSheet: View {
    let appliance: Appliance
    @EnvironmentObject private var applianceService: ApplianceService
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func formatDate(_ isoString: String) -> String {
        if let date = isoParser.date(from: isoString) {
            return dateFormatter.string(from: date)
        }
        let short = ISO8601DateFormatter()
        if let date = short.date(from: isoString) {
            return dateFormatter.string(from: date)
        }
        return isoString
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        detailsSection
                        warrantySection
                        if let notes = appliance.notes, !notes.isEmpty {
                            notesSection(notes)
                        }
                        deleteButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(appliance.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
            }
            .confirmationDialog("Delete \"\(appliance.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await applianceService.delete(appliance)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                ColoredIconBadge(icon: appliance.categoryIcon, color: appliance.categoryColor, size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(appliance.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(appliance.category.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.45))
                    Text(appliance.warrantyStatus)
                        .font(AppFont.captionStrong)
                        .foregroundStyle(appliance.warrantyColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(appliance.warrantyColor.opacity(0.13), in: Capsule())
                }
                Spacer()
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Details")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if let brand = appliance.brand, !brand.isEmpty {
                        infoRow(icon: "building.2.fill", label: "Brand", value: brand)
                        rowDivider
                    }
                    if let model = appliance.modelNumber, !model.isEmpty {
                        infoRow(icon: "number.circle.fill", label: "Model", value: model)
                        rowDivider
                    }
                    if let serial = appliance.serialNumber, !serial.isEmpty {
                        infoRow(icon: "barcode", label: "Serial", value: serial)
                        rowDivider
                    }
                    if let location = appliance.location, !location.isEmpty {
                        infoRow(icon: "mappin.circle.fill", label: "Location", value: location)
                    }
                }
            }
        }
    }

    private var warrantySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Purchase & Warranty")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if let date = appliance.purchaseDate {
                        infoRow(icon: "calendar", label: "Purchased", value: Self.formatDate(date))
                        rowDivider
                    }
                    if let warranty = appliance.warrantyUntil {
                        infoRow(icon: "shield.fill", label: "Warranty Until", value: Self.formatDate(warranty),
                                valueColor: appliance.warrantyColor)
                        rowDivider
                    }
                    if let price = appliance.purchasePrice, price > 0 {
                        infoRow(icon: "banknote.fill", label: "Purchase Price", value: String(format: "%.2f", price))
                    }
                }
            }
        }
    }

    private func notesSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Notes")
            GlassCard {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
            HapticFeedback.warning()
        } label: {
            Label("Delete Appliance", systemImage: "trash")
                .font(AppFont.body)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.label)
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .textCase(.uppercase)
    }

    private func infoRow(icon: String, label: LocalizedStringKey, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(AppFont.footnote)
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}
