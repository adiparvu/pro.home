import SwiftUI
import PhotosUI
import Supabase

extension PropertyElementDetailView {

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
                        StatRow(label: "Estimated value", value: formatted, valueColor: Color(red: 0.2, green: 0.8, blue: 0.4))
                    }
                }
            }

            if localElement.isElectric || (localElement.automationSystem?.isEmpty == false) {
                GlassCard(padding: 14) {
                    VStack(spacing: 10) {
                        SectionHeader("Automation")
                        StatRow(label: "Electric",
                                value: localElement.isElectric ? String(localized: "Yes") : String(localized: "No"),
                                valueColor: localElement.isElectric ? Color(red: 0.2, green: 0.8, blue: 0.4) : .secondary)
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
                            .font(.system(size: 20))
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

    var locationSection: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: localElement.coordinate == nil ? "mappin.slash" : "mappin.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map location").font(.subheadline.weight(.medium))
                    Text(LocalizedStringKey(localElement.coordinate == nil ? "Not placed" : "Placed on map"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showLocationPicker = true } label: {
                    Text(LocalizedStringKey(localElement.coordinate == nil ? "Place" : "Change"))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.accentColor))
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

    var emptyRecordsView: some View {
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

    func formatted(date: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: date) else { return date }
        let out = DateFormatter(); out.dateStyle = .medium; out.locale = .current
        return out.string(from: d)
    }
}
