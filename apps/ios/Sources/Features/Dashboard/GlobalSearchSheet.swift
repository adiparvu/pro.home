import SwiftUI

struct GlobalSearchSheet: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var plantService: PlantService
    @EnvironmentObject private var deliveryService: DeliveryService
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool

    private var taskResults: [MaintenanceTask] {
        guard query.count >= 2 else { return [] }
        return taskService.tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var docResults: [DocumentModel] {
        guard query.count >= 2 else { return [] }
        return documentService.documents.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var plantResults: [Plant] {
        guard query.count >= 2 else { return [] }
        let q = query.lowercased()
        return plantService.plants.filter {
            $0.name.lowercased().contains(q) ||
            ($0.species?.lowercased().contains(q) ?? false) ||
            ($0.location?.lowercased().contains(q) ?? false)
        }
    }

    private var deliveryResults: [Delivery] {
        guard query.count >= 2 else { return [] }
        let q = query.lowercased()
        return deliveryService.deliveries.filter {
            $0.description.lowercased().contains(q) ||
            $0.carrier.lowercased().contains(q) ||
            $0.trackingNumber.lowercased().contains(q)
        }
    }

    private var hasResults: Bool {
        !taskResults.isEmpty || !docResults.isEmpty ||
        !plantResults.isEmpty || !deliveryResults.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                Divider().opacity(0.3)

                Group {
                    if query.count < 2 {
                        promptState
                    } else if !hasResults {
                        noResultsState
                    } else {
                        resultsView
                    }
                }
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Global Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .onAppear { focused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Tasks, documents, properties…", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .focused($focused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("Search across the entire app")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text("Tasks · Plants · Documents · Deliveries")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "questionmark.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No results for")
                .font(.system(size: 15))
                .foregroundStyle(Color.primary.opacity(0.45))
            Text("„\(query)"")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if !taskResults.isEmpty {
                    resultSection("Tasks", icon: "checklist", color: .blue) {
                        ForEach(taskResults.prefix(8)) { task in
                            resultRow(task.title,
                                      subtitle: task.dueDateDisplay,
                                      icon: "checklist", color: .blue,
                                      isLast: task.id == taskResults.prefix(8).last?.id)
                        }
                    }
                }
                if !plantResults.isEmpty {
                    resultSection("Plants", icon: "leaf.fill", color: Color(red: 0.15, green: 0.80, blue: 0.40)) {
                        ForEach(plantResults.prefix(8)) { plant in
                            resultRow("\(plant.emoji) \(plant.name)",
                                      subtitle: plant.needsWatering ? "Needs watering" : plant.wateringLabel,
                                      icon: "leaf.fill", color: Color(red: 0.15, green: 0.80, blue: 0.40),
                                      isLast: plant.id == plantResults.prefix(8).last?.id)
                        }
                    }
                }
                if !docResults.isEmpty {
                    resultSection("Documents", icon: "doc.fill", color: .orange) {
                        ForEach(docResults.prefix(8)) { doc in
                            resultRow(doc.name,
                                      subtitle: doc.expiresDisplay ?? "No expiry date",
                                      icon: "doc.fill", color: .orange,
                                      isLast: doc.id == docResults.prefix(8).last?.id)
                        }
                    }
                }
                if !deliveryResults.isEmpty {
                    resultSection("Deliveries", icon: "shippingbox.fill", color: .orange) {
                        ForEach(deliveryResults.prefix(8)) { delivery in
                            resultRow(delivery.description,
                                      subtitle: "\(delivery.carrier) · \(delivery.statusLabel)",
                                      icon: delivery.statusIcon, color: delivery.statusColor,
                                      isLast: delivery.id == deliveryResults.prefix(8).last?.id)
                        }
                    }
                }
                Spacer(minLength: 60)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func resultSection<C: View>(_ title: String, icon: String, color: Color,
                                         @ViewBuilder content: () -> C) -> some View {
        let innerContent = content()
        return VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .tracking(0.5)
                .padding(.leading, 4)
            GlassCard(padding: 0) {
                VStack(spacing: 0) { innerContent }
            }
        }
    }

    private func resultRow(_ title: String, subtitle: String,
                           icon: String, color: Color, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.22))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 0.5)
                    .padding(.leading, 56)
            }
        }
    }
}
