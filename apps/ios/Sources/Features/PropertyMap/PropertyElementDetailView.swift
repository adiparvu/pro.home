import SwiftUI
import PhotosUI
import Supabase

struct PropertyElementDetailView: View {
    let element: PropertyElement

    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DetailTab = .info
    @State private var showAddRecord = false
    @State private var showEditElement = false
    @State private var localElement: PropertyElement
    @State private var showDeleteConfirm = false
    @State private var showLocationPicker = false
    @State private var showLinkDocument = false
    @State private var showLinkTask = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isUploading = false

    init(element: PropertyElement) {
        self.element = element
        _localElement = State(initialValue: element)
    }

    enum DetailTab: String, CaseIterable {
        case info      = "Info"
        case records   = "History"
        case documents = "Documents"
        case tasks     = "Tasks"

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
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete element", systemImage: "trash")
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
        .sheet(isPresented: $showLocationPicker) {
            ObjectLocationPicker(element: localElement)
        }
        .sheet(isPresented: $showLinkDocument) {
            DocumentLinkPicker(elementId: localElement.id)
                .environmentObject(documentService)
        }
        .sheet(isPresented: $showLinkTask) {
            TaskLinkPicker(elementId: localElement.id)
                .environmentObject(taskService)
        }
        .onChange(of: photoItems) { _, items in
            Task { await uploadPhotos(items) }
        }
        .confirmationDialog("Delete \(localElement.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
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
                    Text("Technical condition")
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
            photosSection
            locationSection

            if let desc = localElement.description {
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Description", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(desc)
                            .font(.subheadline)
                    }
                }
            }

            // Technical details grid
            GlassCard(padding: 14) {
                VStack(spacing: 10) {
                    SectionHeader("Technical details")
                    if let brand = localElement.brand {
                        StatRow(label: "Brand", value: brand)
                    }
                    if let model = localElement.model {
                        StatRow(label: "Model", value: model)
                    }
                    if let serial = localElement.serialNumber {
                        StatRow(label: "Serial", value: serial)
                    }
                    if let purchase = localElement.purchaseDate {
                        StatRow(label: "Purchase date", value: formatted(date: purchase))
                    }
                    if let warranty = localElement.warrantyUntil {
                        StatRow(label: "Warranty until", value: formatted(date: warranty), valueColor: localElement.warrantyStatus.color)
                    }
                    if let value = localElement.estimatedValue {
                        let formatted = currencyService.formatted(value, from: localElement.valueCurrency, preferred: appSettings.preferredCurrency)
                        StatRow(label: "Estimated value", value: formatted, valueColor: Color(red: 0.2, green: 0.8, blue: 0.4))
                    }
                }
            }

            if let notes = localElement.notes, !notes.isEmpty {
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Notes", systemImage: "note.text")
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
                        SectionHeader("Summary")
                        StatRow(label: "Total records", value: "\(recs.count)")
                        if totalCost > 0 {
                            StatRow(label: "Total costs", value: currencyService.formatted(totalCost, from: "EUR", preferred: appSettings.preferredCurrency),
                                    valueColor: Color(red: 0.2, green: 0.8, blue: 0.4))
                        }
                        if let last = lastDate {
                            StatRow(label: "Last record", value: formatted(date: last))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if isUploading { ProgressView().scaleEffect(0.7) }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.accentColor)
                    }
                }
                if localElement.photos.isEmpty {
                    Text("No photos yet")
                        .font(.caption).foregroundStyle(.tertiary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(localElement.photos, id: \.self) { urlStr in
                                if let url = URL(string: urlStr) {
                                    AsyncImage(url: url) { phase in
                                        if case .success(let img) = phase {
                                            img.resizable().scaledToFill()
                                        } else {
                                            Rectangle().fill(Color.primary.opacity(0.06))
                                                .overlay(ProgressView().scaleEffect(0.6))
                                        }
                                    }
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task { await deletePhoto(urlStr) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var locationSection: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: localElement.coordinate == nil ? "mappin.slash" : "mappin.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map location").font(.subheadline.weight(.medium))
                    Text(localElement.coordinate == nil ? "Not placed" : "Placed on map")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showLocationPicker = true } label: {
                    Text(localElement.coordinate == nil ? "Place" : "Change")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }
        var urls = localElement.photos
        let uid = supabase.auth.currentSession?.user.id.uuidString ?? "anon"
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let path = "\(uid)/elements/\(localElement.id.uuidString)/\(UUID().uuidString).jpg"
            try? await supabase.storage.from("documents")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            if let url = try? supabase.storage.from("documents").getPublicURL(path: path) {
                urls.append(url.absoluteString)
            }
        }
        await elementService.updatePhotos(elementId: localElement.id, urls: urls)
        photoItems = []
    }

    private func deletePhoto(_ urlStr: String) async {
        var urls = localElement.photos
        urls.removeAll { $0 == urlStr }
        await elementService.updatePhotos(elementId: localElement.id, urls: urls)
    }

    // MARK: - Records Tab

    private var recordsTab: some View {
        VStack(spacing: 12) {
            HStack {
                Text("History & Work")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    HapticFeedback.selection()
                    showAddRecord = true
                } label: {
                    Label("Add", systemImage: "plus")
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
                Text("No records")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Add the first job, cost or note")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Documents Tab

    private var documentsTab: some View {
        let linked = documentService.documents(forElement: localElement.id)
        return VStack(spacing: 12) {
            HStack {
                Text("Linked documents")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    HapticFeedback.selection()
                    showLinkDocument = true
                } label: {
                    Label("Link", systemImage: "link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.29, green: 0.56, blue: 0.89)))
                }
            }
            if linked.isEmpty {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 32)).foregroundStyle(Color.secondary.opacity(0.5))
                        Text("No linked documents")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Link manuals, warranties or invoices to this item")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            } else {
                ForEach(linked) { doc in
                    LinkedDocumentRow(
                        doc: doc,
                        onOpen: {
                            if let url = URL(string: doc.fileUrl) { UIApplication.shared.open(url) }
                        },
                        onUnlink: { Task { await documentService.setElement(nil, for: doc) } }
                    )
                }
            }
        }
    }

    // MARK: - Tasks Tab

    private var tasksTab: some View {
        let linked = taskService.tasks(forElement: localElement.id)
        return VStack(spacing: 12) {
            HStack {
                Text("Linked tasks")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    HapticFeedback.selection()
                    showLinkTask = true
                } label: {
                    Label("Link", systemImage: "link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.29, green: 0.56, blue: 0.89)))
                }
            }
            if linked.isEmpty {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: "checklist")
                            .font(.system(size: 32)).foregroundStyle(Color.secondary.opacity(0.5))
                        Text("No linked tasks")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Link maintenance tasks to this item")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            } else {
                ForEach(linked) { task in
                    LinkedTaskRow(
                        task: task,
                        onToggle: { Task { await taskService.toggleComplete(task) } },
                        onUnlink: { Task { await taskService.setElement(nil, for: task) } }
                    )
                }
            }
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
                    .foregroundStyle(selected == tab ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected == tab ? Color.primary.opacity(0.12) : Color.clear)
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

// MARK: - Linked document row

private struct LinkedDocumentRow: View {
    let doc: DocumentModel
    let onOpen: () -> Void
    let onUnlink: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: doc.categoryIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(doc.category.capitalized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 16)).foregroundStyle(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onUnlink) {
                Label("Unlink", systemImage: "link.badge.minus")
            }
        }
    }
}

// MARK: - Document link picker

private struct DocumentLinkPicker: View {
    let elementId: UUID
    @EnvironmentObject private var documentService: DocumentService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    let available = documentService.documents.filter { $0.elementId == nil }
                    VStack(spacing: 10) {
                        if available.isEmpty {
                            Text("All documents are already linked or no documents exist.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40).padding(.horizontal, 24)
                        } else {
                            ForEach(available) { doc in
                                Button {
                                    Task {
                                        await documentService.setElement(elementId, for: doc)
                                        dismiss()
                                    }
                                } label: {
                                    GlassCard(padding: 12) {
                                        HStack(spacing: 12) {
                                            Image(systemName: doc.categoryIcon)
                                                .font(.system(size: 15)).foregroundStyle(.accentColor).frame(width: 28)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(doc.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                                Text(doc.category.capitalized).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle.fill").foregroundStyle(.accentColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Link document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Linked task row

private struct LinkedTaskRow: View {
    let task: MaintenanceTask
    let onToggle: () -> Void
    let onUnlink: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(task.isCompleted ? Color(red: 0.2, green: 0.8, blue: 0.45) : Color.secondary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(task.priorityColor).frame(width: 6, height: 6)
                        Text(task.dueDateDisplay).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onUnlink) {
                Label("Unlink", systemImage: "link.badge.minus")
            }
        }
    }
}

// MARK: - Task link picker

private struct TaskLinkPicker: View {
    let elementId: UUID
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    let available = taskService.tasks.filter { $0.elementId == nil && !$0.isCompleted }
                    VStack(spacing: 10) {
                        if available.isEmpty {
                            Text("No tasks available to link.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40).padding(.horizontal, 24)
                        } else {
                            ForEach(available) { task in
                                Button {
                                    Task {
                                        await taskService.setElement(elementId, for: task)
                                        dismiss()
                                    }
                                } label: {
                                    GlassCard(padding: 12) {
                                        HStack(spacing: 12) {
                                            Circle().fill(task.priorityColor).frame(width: 8, height: 8)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(task.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                                Text(task.dueDateDisplay).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle.fill").foregroundStyle(.accentColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Link task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
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
