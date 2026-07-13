import SwiftUI

// MARK: - ApplianceDetailSheet
//
// The appliance's file: hero (real photo when one exists), identifiers with
// tap-to-copy, the warranty card (tri-state countdown, never a dead label —
// "no warranty" carries a CTA into edit), honest age vs. the curated
// category lifespan (ApplianceLifespan, ranges only), the service book, its
// linked papers (reusing Document Intelligence links) and a real bridge to
// the task system for periodic service — no invented schedules.

struct ApplianceDetailSheet: View {
    let appliance: Appliance
    @Environment(ApplianceService.self) private var applianceService
    @Environment(DocumentService.self) private var documentService
    @Environment(TaskService.self) private var taskService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var showEdit = false
    @State private var showAttachDocument = false
    /// Bumps to make LinkedDocumentsSection re-query after a new link.
    @State private var documentsRefresh = 0
    /// The value just copied — drives the transient "Copied" confirmation.
    @State private var copiedValue: String?
    @State private var serviceTaskCreated = false

    /// The live row — edits land in the service array; the sheet must not
    /// keep showing the stale copy it was presented with.
    private var current: Appliance {
        applianceService.appliances.first { $0.id == appliance.id } ?? appliance
    }

    private var warranty: ApplianceWarrantyPresentation { .init(current) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        detailsSection
                        warrantySection
                        ageSection
                        ApplianceServiceBookSection(appliance: current)
                        revisionSection
                        LinkedDocumentsSection(targetKind: .appliance, targetId: current.id)
                            .id(documentsRefresh)
                        if let notes = current.notes, !notes.isEmpty {
                            notesSection(notes)
                        }
                        deleteButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle(current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        showEdit = true
                        HapticFeedback.impact(.light)
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .sheet(isPresented: $showEdit) {
                ApplianceFormSheet(editing: current)
                    .environment(applianceService)
            }
            .sheet(isPresented: $showAttachDocument) {
                ApplianceAttachDocumentSheet(appliance: current) {
                    documentsRefresh += 1
                }
                .environment(documentService)
            }
            .confirmationDialog("Delete \"\(current.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await applianceService.delete(current)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Header (photo hero only when a real photo exists)

    private var headerCard: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                if let urlString = current.photoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                                .overlay(ProgressView().tint(.secondary))
                        }
                    }
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
                }
                HStack(spacing: 16) {
                    ColoredIconBadge(icon: current.categoryIcon, color: current.categoryColor, size: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(current.name)
                            .font(AppFont.scaled(20, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(current.category.displayName)
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        Text(verbatim: warranty.text)
                            .font(AppFont.captionStrong)
                            .foregroundStyle(warranty.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(
                                warranty.isQuiet
                                    ? Color.primary.opacity(AppOpacity.hairline)
                                    : warranty.color.opacity(0.13),
                                in: Capsule())
                    }
                    Spacer()
                }
                .padding(20)
            }
        }
    }

    // MARK: - Details (model/serial tap-to-copy)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Details")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if let brand = current.brand, !brand.isEmpty {
                        infoRow(icon: "building.2.fill", label: "Brand", value: brand)
                        rowDivider
                    }
                    if let model = current.modelNumber, !model.isEmpty {
                        copyRow(icon: "number.circle.fill", label: "Model", value: model)
                        rowDivider
                    }
                    if let serial = current.serialNumber, !serial.isEmpty {
                        copyRow(icon: "barcode", label: "Serial", value: serial)
                        rowDivider
                    }
                    if let location = current.location, !location.isEmpty {
                        infoRow(icon: "mappin.circle.fill", label: "Location", value: location)
                    }
                }
            }
        }
    }

    /// An info row whose value copies to the clipboard on tap, confirming
    /// inline — the affordance every serial number deserves.
    private func copyRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            HapticFeedback.success()
            withAnimation(.snappy(duration: 0.25)) { copiedValue = value }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.smooth(duration: 0.3)) {
                    if copiedValue == value { copiedValue = nil }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                Text(label)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(.secondary)
                Spacer()
                if copiedValue == value {
                    Label("Copied", systemImage: "checkmark")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.brandSuccess)
                        .transition(.opacity)
                } else {
                    Text(value)
                        .font(AppFont.footnote)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                    Image(systemName: "doc.on.doc")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("appliance_tap_copy"))
    }

    // MARK: - Purchase & warranty

    private var warrantySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Purchase & Warranty")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if let date = current.purchaseDateValue {
                        infoRow(icon: "calendar", label: "Purchased",
                                value: AppDate.monthDayYear.string(from: date))
                        rowDivider
                    }
                    warrantyRow
                    if let price = current.purchasePrice, price > 0 {
                        rowDivider
                        // The table stores a bare number; it is entered and
                        // shown in the household's preferred currency.
                        infoRow(icon: "banknote.fill", label: "Purchase Price",
                                value: CurrencyService.money(price, code: appSettings.preferredCurrency))
                    }
                    rowDivider
                    attachDocumentRow
                }
            }
        }
    }

    @ViewBuilder private var warrantyRow: some View {
        if let days = current.warrantyDaysRemaining, let date = current.warrantyDateValue {
            HStack(spacing: 12) {
                Image(systemName: "shield.fill")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                Text("Warranty Until")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: AppDate.monthDayYear.string(from: date))
                        .font(AppFont.footnote)
                        .foregroundStyle(warranty.color)
                    Text(verbatim: days < 0
                        ? String(format: String(localized: "appliance_warranty_expired_on %@"),
                                 AppDate.monthDayYear.string(from: date))
                        : String.localizedStringWithFormat(
                            String(localized: "appliance_warranty_days %lld"), days))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(warranty.color.opacity(0.8))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        } else {
            // No warranty on file → the row IS the fix, never a dead label.
            Button {
                showEdit = true
                HapticFeedback.impact(.light)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shield.slash")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .frame(width: 24)
                    Text("No Warranty")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("appliance_warranty_none_cta")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Links an existing document (invoice, certificate) to this appliance —
    /// the same document_links table the Documents feature writes.
    private var attachDocumentRow: some View {
        Button {
            showAttachDocument = true
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "paperclip")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                Text("appliance_attach_doc")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Age & typical lifespan (honest ranges only)

    private var lifespanRange: ClosedRange<Int>? {
        ApplianceLifespan.typicalYears(for: current.category)
    }

    @ViewBuilder private var ageSection: some View {
        let age = current.ageYears
        if age != nil || lifespanRange != nil {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("appliance_age_section")
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        if let age {
                            infoRow(icon: "clock.arrow.circlepath",
                                    label: "appliance_age_label",
                                    value: ageDisplay(age))
                        }
                        if let range = lifespanRange {
                            if age != nil { rowDivider }
                            infoRow(icon: "hourglass",
                                    label: "appliance_lifespan_label",
                                    value: String(format: String(localized: "appliance_lifespan_range %lld %lld"),
                                                  range.lowerBound, range.upperBound))
                        }
                        // The progress line exists ONLY when a real purchase
                        // date meets a curated range — no fabricated precision.
                        if let age, let range = lifespanRange {
                            rowDivider
                            lifespanProgress(age: age, range: range)
                        }
                    }
                }
                if lifespanRange != nil {
                    Text("appliance_lifespan_note")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .padding(.horizontal, AppSpacing.xxs)
                }
            }
        }
    }

    private func ageDisplay(_ years: Double) -> String {
        // localizedStringWithFormat resolves the catalog's plural variations
        // (ro: an/ani/de ani); plain String(format:) won't.
        if years < 1 {
            let months = max(0, Int((years * 12).rounded(.down)))
            return String.localizedStringWithFormat(String(localized: "appliance_age_months %lld"), months)
        }
        return String.localizedStringWithFormat(String(localized: "appliance_age_years %lld"), Int(years.rounded(.down)))
    }

    private func lifespanProgress(age: Double, range: ClosedRange<Int>) -> some View {
        let wholeYears = Int(age.rounded(.down))
        let fraction = min(age / Double(range.upperBound), 1)
        return VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: fraction)
                .tint(fraction >= 1 ? Color.brandWarning : Color.accentColor)
            Text(verbatim: String(format: String(localized: "appliance_lifespan_progress %lld %lld %lld"),
                                  wholeYears, range.lowerBound, range.upperBound))
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Periodic service (honest task bridge — no invented schedule)

    private var revisionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("appliance_revision_section")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("appliance_revision_hint")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task { await createServiceTask() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: serviceTaskCreated ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill")
                                .font(AppFont.scaled(13, weight: .semibold))
                            (serviceTaskCreated ? Text("appliance_task_created") : Text("appliance_task_cta"))
                                .font(AppFont.captionEmphasis)
                        }
                        .foregroundStyle(serviceTaskCreated ? Color.brandSuccess : Color.accentColor)
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 8)
                        .glassCapsule()
                    }
                    .buttonStyle(.plain)
                    .disabled(serviceTaskCreated)
                }
            }
        }
    }

    private func createServiceTask() async {
        let title = String(format: String(localized: "appliance_task_title %@"), current.name)
        let subject = [current.name, current.brand].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let description = String(format: String(localized: "appliance_task_notes %@"), subject)
        do {
            _ = try await taskService.addTask(NewTaskPayload(
                propertyId: current.propertyId,
                title: title,
                description: description,
                dueDate: nil,
                priority: "medium",
                category: "maintenance",
                assigneeIds: [],
                assigneeNames: []
            ))
            HapticFeedback.success()
            withAnimation(.snappy(duration: 0.25)) { serviceTaskCreated = true }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.smooth(duration: 0.3)) { serviceTaskCreated = false }
            }
        } catch {
            HapticFeedback.error()
        }
    }

    // MARK: - Notes / delete / shared bits

    private func notesSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Notes")
            GlassCard {
                Text(text)
                    .font(AppFont.scaled(14))
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
                .padding(.vertical, AppSpacing.base)
                .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.label)
            .foregroundStyle(.secondary)
            .padding(.leading, AppSpacing.xs)
            .textCase(.uppercase)
    }

    private func infoRow(icon: String, label: LocalizedStringKey, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(label)
                .font(AppFont.scaled(14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(AppFont.footnote)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}

// MARK: - Attach document picker
//
// Links an already-uploaded document to this appliance via document_links —
// the exact mechanism DocumentRelationsSection uses from the document side,
// just pointed the other way. Documents already linked are hidden.

private struct ApplianceAttachDocumentSheet: View {
    let appliance: Appliance
    var onLinked: () -> Void

    @Environment(DocumentService.self) private var documentService
    @Environment(\.dismiss) private var dismiss

    @State private var linksService = DocumentLinksService()
    @State private var alreadyLinked: Set<UUID> = []
    @State private var search = ""
    @State private var linkingId: UUID?

    private var candidates: [DocumentModel] {
        var docs = documentService.documents.filter { !alreadyLinked.contains($0.id) }
        if !search.isEmpty {
            docs = docs.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }
        return docs
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                if candidates.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(AppFont.scaled(34))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        Text("appliance_attach_doc_empty")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xxl)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(candidates) { doc in
                                docRow(doc)
                                Rectangle().fill(Color.primary.opacity(0.05))
                                    .frame(height: 0.5).padding(.leading, 58)
                            }
                        }
                        .padding(.top, AppSpacing.sm)
                    }
                }
            }
            .navigationTitle(Text("appliance_attach_doc"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
            }
            .task {
                if documentService.documents.isEmpty { await documentService.load() }
                let ids = await DocumentLinksService.documentIds(forTarget: .appliance, targetId: appliance.id)
                alreadyLinked = Set(ids)
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
    }

    private func docRow(_ doc: DocumentModel) -> some View {
        Button {
            guard linkingId == nil else { return }
            linkingId = doc.id
            Task {
                let ok = await linksService.addLink(documentId: doc.id, kind: .appliance, targetId: appliance.id)
                linkingId = nil
                if ok {
                    HapticFeedback.success()
                    onLinked()
                    dismiss()
                } else {
                    HapticFeedback.error()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: doc.categoryIcon)
                    .font(AppFont.scaled(18))
                    .foregroundStyle(documentCategoryColor(doc.category))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name)
                        .font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    Text(DocumentTypeDisplay.name(doc.category))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                Spacer()
                if linkingId == doc.id {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(AppFont.scaled(17))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
