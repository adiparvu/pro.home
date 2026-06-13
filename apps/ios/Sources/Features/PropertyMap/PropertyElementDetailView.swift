import SwiftUI

struct PropertyElementDetailView: View {
    let element: PropertyElement

    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DetailTab = .info
    @State private var showAddRecord = false
    @State private var showEditElement = false
    @State private var localElement: PropertyElement
    @State private var showDeleteConfirm = false

    init(element: PropertyElement) {
        self.element = element
        _localElement = State(initialValue: element)
    }

    enum DetailTab: String, CaseIterable {
        case info      = "Info"
        case records   = "Istoric"
        case documents = "Documente"
        case tasks     = "Taskuri"

        var icon: String {
            switch self {
            case .info:      return "info.circle"
            case .records:   return "clock.arrow.circlepath"
            case .documents: return "doc.fill"
            case .tasks:     return "checklist"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header with element identity
                    elementHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    // Health bar
                    healthSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // Tab bar
                    DetailTabBar(selected: $selectedTab)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    // Content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case .info:      infoTab
                            case .records:   recordsTab
                            case .documents: documentsTab
                            case .tasks:     tasksTab
                            }
                            Spacer(minLength: 60)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 22))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEditElement = true } label: {
                            Label("Editează", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Șterge element", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .sheet(isPresented: $showAddRecord) {
            AddElementRecordView(element: localElement) { payload in
                Task { await elementService.addRecord(payload) }
            }
        }
        .sheet(isPresented: $showEditElement) {
            EditPropertyElementView(element: $localElement) {
                Task { await elementService.update(localElement) }
            }
        }
        .confirmationDialog("Ștergi \(localElement.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Șterge", role: .destructive) {
                Task {
                    await elementService.delete(localElement)
                    dismiss()
                }
            }
        }
        .task {
            await elementService.loadRecords(elementId: localElement.id)
        }
        .onReceive(elementService.$elements) { updated in
            if let fresh = updated.first(where: { $0.id == localElement.id }) {
                localElement = fresh
            }
        }
    }

    // MARK: - Header

    private var elementHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(localElement.elementType.accentColor.opacity(0.2))
                    .frame(width: 60, height: 60)
                Image(systemName: localElement.elementType.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(localElement.elementType.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(localElement.name)
                    .font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    Text(localElement.elementType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    conditionBadge
                }
                if let brand = localElement.brand, let model = localElement.model {
                    Text("\(brand) \(model)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let brand = localElement.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            warrantyBadge
        }
    }

    private var conditionBadge: some View {
        Text(localElement.technicalCondition.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(localElement.technicalCondition.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(localElement.technicalCondition.color.opacity(0.15)))
    }

    private var warrantyBadge: some View {
        let status = localElement.warrantyStatus
        return VStack(spacing: 2) {
            Image(systemName: status == .none ? "shield.slash" : "shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(status.color)
            Text(status.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(status.color)
                .multilineTextAlignment(.center)
        }
        .frame(width: 60)
    }

    // MARK: - Health

    private var healthSection: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 8) {
                HStack {
                    Text("Stare tehnică")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(localElement.healthScore)/100")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(localElement.healthColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 8)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [localElement.healthColor.opacity(0.7), localElement.healthColor],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(localElement.healthScore) / 100, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        VStack(spacing: 12) {
            if let desc = localElement.description {
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Descriere", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(desc)
                            .font(.subheadline)
                    }
                }
            }

            // Technical details grid
            GlassCard(padding: 14) {
                VStack(spacing: 10) {
                    SectionHeader("Detalii tehnice")
                    if let brand = localElement.brand {
                        StatRow(label: "Marcă", value: brand)
                    }
                    if let model = localElement.model {
                        StatRow(label: "Model", value: model)
                    }
                    if let serial = localElement.serialNumber {
                        StatRow(label: "Serie", value: serial)
                    }
                    if let purchase = localElement.purchaseDate {
                        StatRow(label: "Data achiziției", value: formatted(date: purchase))
                    }
                    if let warranty = localElement.warrantyUntil {
                        StatRow(label: "Garanție până", value: formatted(date: warranty), valueColor: localElement.warrantyStatus.color)
                    }
                    if let value = localElement.estimatedValue {
                        let formatted = currencyService.formatted(value, from: localElement.valueCurrency, preferred: appSettings.preferredCurrency)
                        StatRow(label: "Valoare estimată", value: formatted, valueColor: Color(red: 0.2, green: 0.8, blue: 0.4))
                    }
                }
            }

            if let notes = localElement.notes, !notes.isEmpty {
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Note", systemImage: "note.text")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Quick stats from records
            let recs = elementService.records[localElement.id] ?? []
            if !recs.isEmpty {
                let totalCost = recs.compactMap(\.cost).reduce(0, +)
                let lastDate = recs.first?.recordDate
                GlassCard(padding: 14) {
                    VStack(spacing: 10) {
                        SectionHeader("Sumar")
                        StatRow(label: "Total înregistrări", value: "\(recs.count)")
                        if totalCost > 0 {
                            StatRow(label: "Total costuri", value: currencyService.formatted(totalCost, from: "EUR", preferred: appSettings.preferredCurrency),
                                    valueColor: Color(red: 0.2, green: 0.8, blue: 0.4))
                        }
                        if let last = lastDate {
                            StatRow(label: "Ultima înregistrare", value: formatted(date: last))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Records Tab

    private var recordsTab: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Istoric & Lucrări")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    HapticFeedback.selection()
                    showAddRecord = true
                } label: {
                    Label("Adaugă", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.29, green: 0.56, blue: 0.89)))
                }
            }

            let recs = elementService.records[localElement.id] ?? []
            if recs.isEmpty {
                emptyRecordsView
            } else {
                ForEach(recs) { record in
                    ElementRecordRow(record: record) {
                        Task { await elementService.deleteRecord(record) }
                    }
                }
            }
        }
    }

    private var emptyRecordsView: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 32)).foregroundStyle(Color.secondary.opacity(0.5))
                Text("Fără înregistrări")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Adaugă prima lucrare, cost sau notă")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Documents Tab

    private var documentsTab: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 32)).foregroundStyle(Color.secondary.opacity(0.5))
                Text("Documente element")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Integrare completă cu DocumentsView — filtrare după element disponibilă în versiunea următoare")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tasks Tab

    private var tasksTab: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 32)).foregroundStyle(Color.secondary.opacity(0.5))
                Text("Taskuri element")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Asociere taskuri per element disponibilă în versiunea următoare")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Helpers

    private func formatted(date: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return date }
        let out = DateFormatter(); out.dateStyle = .medium; out.locale = .current
        return out.string(from: d)
    }
}

// MARK: - Detail Tab Bar

private struct DetailTabBar: View {
    @Binding var selected: PropertyElementDetailView.DetailTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PropertyElementDetailView.DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25)) { selected = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: selected == tab ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: selected == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selected == tab ? .white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected == tab ? Color.primary.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(record.recordType.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(record.recordType.displayName)
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
                            .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.4))
                    }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Șterge", systemImage: "trash")
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

// MARK: - SectionHeader helper

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
