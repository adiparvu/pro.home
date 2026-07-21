import SwiftUI
import PhotosUI

extension PropertyElementDetailView {

    // MARK: - Service schedule (predictive phase 2)
    //
    // The household sets a cadence; the proactive engine turns
    // (last service + interval) into a due prediction. Everything saves
    // through the same localElement → elementService.update path the page
    // already uses.

    var serviceScheduleCard: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 10) {
                SectionHeader("Service schedule")
                HStack {
                    Text("Service interval")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.secondaryTextColor)
                    Spacer()
                    Menu {
                        Picker("", selection: Binding(
                            get: { localElement.serviceIntervalMonths },
                            set: { newValue in
                                localElement.serviceIntervalMonths = newValue
                                if newValue == nil { localElement.lastServiceAt = nil }
                                Task { await elementService.update(localElement) }
                            })) {
                            Text("No cadence").tag(Int?.none)
                            Text("Every 3 months").tag(Int?.some(3))
                            Text("Every 6 months").tag(Int?.some(6))
                            Text("Yearly").tag(Int?.some(12))
                            Text("Every 2 years").tag(Int?.some(24))
                        }
                    } label: {
                        Text(serviceIntervalLabel)
                            .font(AppFont.scaled(14, weight: .medium))
                            .foregroundStyle(localElement.serviceIntervalMonths == nil
                                ? Color.secondaryTextColor : Color.accentColor)
                    }
                }
                if localElement.serviceIntervalMonths != nil {
                    if let last = localElement.lastServiceAt {
                        StatRow(label: "Last service", value: formatted(date: last))
                    }
                    if let due = localElement.nextServiceDue {
                        StatRow(label: "Next service",
                                value: due.formatted(date: .abbreviated, time: .omitted),
                                valueColor: due < Date() ? Color.brandWarning : Color.brandSuccess)
                    }
                    Button {
                        HapticFeedback.success()
                        localElement.lastServiceAt = AppDate.day.string(from: Date())
                        Task { await elementService.update(localElement) }
                    } label: {
                        Label("Serviced today", systemImage: "checkmark.seal")
                            .font(AppFont.scaled(13, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color.accentColor.opacity(AppOpacity.tintedFill),
                                        in: RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var serviceIntervalLabel: LocalizedStringKey {
        switch localElement.serviceIntervalMonths {
        case 3:  return "Every 3 months"
        case 6:  return "Every 6 months"
        case 12: return "Yearly"
        case 24: return "Every 2 years"
        default: return "No cadence"
        }
    }

    // MARK: - Info Tab

    var infoTab: some View {
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
                        StatRow(label: "Estimated value", value: formatted, valueColor: Color.brandSuccess)
                    }
                }
            }

            serviceScheduleCard

            if localElement.isElectric || (localElement.automationSystem?.isEmpty == false) {
                GlassCard(padding: 14) {
                    VStack(spacing: 10) {
                        SectionHeader("Automation")
                        StatRow(label: "Electric",
                                value: localElement.isElectric ? String(localized: "Yes") : String(localized: "No"),
                                valueColor: localElement.isElectric ? Color.brandSuccess : .secondary)
                        if let sys = localElement.automationSystem, !sys.isEmpty {
                            StatRow(label: "System", value: sys)
                        }
                    }
                }
            }

            if localElement.isElectric ||
               [.appliances, .security, .energy].contains(localElement.elementType.category) {
                ElementSmartControlSection(elementId: localElement.id)
            }

            ElementTagsSection(elementId: localElement.id)

            ElementObjectsSection(element: localElement)

            ElementAutomationsSection(element: localElement)

            ElementNotesSection(element: localElement)

            if let notes = localElement.notes, !notes.isEmpty {
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Quick note", systemImage: "note.text")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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
                                    valueColor: Color.brandSuccess)
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

    var photosSection: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if isUploading { ProgressView().scaleEffect(0.7) }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFont.scaled(20))
                            .foregroundStyle(Color.accentColor)
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
                                    StorageImage(url: url) { phase in
                                        if case .success(let img) = phase {
                                            img.resizable().scaledToFill()
                                        } else {
                                            Rectangle().fill(Color.primary.opacity(AppOpacity.hairline))
                                                .overlay(ProgressView().scaleEffect(0.6))
                                        }
                                    }
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
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

    var locationSection: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: localElement.coordinate == nil ? "mappin.slash" : "mappin.circle.fill")
                    .font(AppFont.scaled(17))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .glassCircle()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map location").font(.subheadline.weight(.medium))
                    Text(LocalizedStringKey(localElement.coordinate == nil ? "Not placed" : "Placed on map"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showLocationPicker = true } label: {
                    Text(LocalizedStringKey(localElement.coordinate == nil ? "Place" : "Change"))
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
                        .glassCapsule()
                }
                .buttonStyle(.plain)
            }
        }
    }

    func uploadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }
        var urls = localElement.photos
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let url = try? await SignedStorage.uploadPublicImage(
                data, folder: "elements/\(localElement.id.uuidString)") {
                urls.append(url)
            }
        }
        await elementService.updatePhotos(elementId: localElement.id, urls: urls)
        photoItems = []
    }

    func deletePhoto(_ urlStr: String) async {
        var urls = localElement.photos
        urls.removeAll { $0 == urlStr }
        await elementService.updatePhotos(elementId: localElement.id, urls: urls)
    }

    // MARK: - Records Tab

    var recordsTab: some View {
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
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .glassCapsule()
                }
            }

            let recs = elementService.records[localElement.id] ?? []
            if recs.isEmpty {
                emptyRecordsView
            } else {
                ElementCostTimeline(records: recs, currency: localElement.valueCurrency)
                ForEach(recs) { record in
                    ElementRecordRow(record: record) {
                        Task { await elementService.deleteRecord(record) }
                    }
                }
            }
        }
    }

    var emptyRecordsView: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppFont.scaled(32)).foregroundStyle(Color.secondary.opacity(0.5))
                Text("No records")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Add the first job, cost or note")
                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    // MARK: - Documents Tab

    var documentsTab: some View {
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
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
                        .glassCapsule()
                }
            }
            if linked.isEmpty {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.fill")
                            .font(AppFont.scaled(32)).foregroundStyle(Color.secondary.opacity(0.5))
                        Text("No linked documents")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Link manuals, warranties or invoices to this item")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.sm)
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

    var tasksTab: some View {
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
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
                        .glassCapsule()
                }
            }
            if linked.isEmpty {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: "checklist")
                            .font(AppFont.scaled(32)).foregroundStyle(Color.secondary.opacity(0.5))
                        Text("No linked tasks")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Link maintenance tasks to this item")
                            .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.sm)
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

    func formatted(date: String) -> String {
        guard let d = AppDate.day(from: date) else { return date }
        return AppDate.medium.string(from: d)
    }
}
