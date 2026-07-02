import SwiftUI

// MARK: - ElementRecordRow

struct ElementRecordRow: View {
    let record: ElementRecord
    let onDelete: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(record.recordType.color.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: record.recordType.icon)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(record.recordType.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(record.recordType.displayName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let by = record.performedBy {
                            Text("· \(by)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    if let content = record.content {
                        Text(content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let cost = record.cost {
                        Text("−\(formatCost(cost)) \(record.currency)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.brandSuccess)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var formattedDate: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: record.recordDate) else { return record.recordDate }
        let out = DateFormatter(); out.dateStyle = .short; out.locale = .current
        return out.string(from: d)
    }

    private func formatCost(_ cost: Double) -> String {
        String(format: "%.0f", cost)
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }
    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
