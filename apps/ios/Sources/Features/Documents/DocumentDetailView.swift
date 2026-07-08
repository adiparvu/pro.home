import SwiftUI
import QuickLook

// MARK: - Per-device document favorites
//
// Favorites are a personal, per-device concept (like starred chats), so they
// live in UserDefaults rather than the shared document row — starring a document
// doesn't change it for other members.
enum DocumentFavoritesStore {
    private static let key = "prvio.document.favorites"
    static func ids() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func isFavorite(_ id: UUID) -> Bool { ids().contains(id.uuidString) }

    @discardableResult
    static func toggle(_ id: UUID) -> Bool {
        var s = ids()
        let nowFavorite: Bool
        if s.contains(id.uuidString) { s.remove(id.uuidString); nowFavorite = false }
        else { s.insert(id.uuidString); nowFavorite = true }
        UserDefaults.standard.set(Array(s), forKey: key)
        return nowFavorite
    }
}

func documentCategoryColor(_ category: String) -> Color {
    switch category {
    case "warranty":    return .yellow
    case "contract":    return .blue
    case "legal":       return .indigo
    case "insurance":   return Color.brandSuccess
    case "certificate": return .purple
    case "manual":      return .cyan
    case "invoice":     return .orange
    case "permit":      return .teal
    case "tax":         return .pink
    case "utility":     return .mint
    case "photo":       return .pink
    default:            return .gray
    }
}

// MARK: - Long-press preview card

struct DocumentRowPreview: View {
    let doc: DocumentModel
    private var tint: Color { documentCategoryColor(doc.category) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.16)).frame(width: 76, height: 76)
                Image(systemName: doc.categoryIcon).font(AppFont.scaled(30, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(spacing: 4) {
                Text(doc.name).font(AppFont.scaled(17, weight: .semibold))
                    .foregroundStyle(.primary).multilineTextAlignment(.center).lineLimit(2)
                Text(LocalizedStringKey(doc.category.capitalized))
                    .font(AppFont.scaled(12)).foregroundStyle(tint)
                if !doc.fileSizeDisplay.isEmpty {
                    Text(doc.fileSizeDisplay).font(AppFont.scaled(11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(width: 260)
    }
}

// MARK: - Document detail page (pushed, not a sheet)

struct DocumentDetailView: View {
    let doc: DocumentModel
    @Environment(DocumentService.self) private var documentService
    @Environment(\.dismiss) private var dismiss

    @State private var previewURL: URL?
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var isFavorite = false
    // Calendar (D5): the outcome of the last "Add to Calendar" attempt, surfaced
    // honestly — success only when EventKit actually saved the event.
    @State private var calendarOutcome: CalendarOutcome?
    @State private var isAddingToCalendar = false

    /// Always read the freshest copy so edits reflect immediately.
    private var live: DocumentModel { documentService.documents.first { $0.id == doc.id } ?? doc }
    private var tint: Color { documentCategoryColor(live.category) }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    fileCard
                    DocumentFilesSection(documentId: doc.id)
                    DocumentRelationsSection(documentId: doc.id)
                    DocumentHistorySection(documentId: doc.id)
                    richDetailsCard
                    detailsCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticFeedback.selection()
                    isFavorite = DocumentFavoritesStore.toggle(live.id)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .primary)
                }
                .accessibilityLabel(isFavorite ? "Unfavorite" : "Favorite")
            }
        }
        .onAppear { isFavorite = DocumentFavoritesStore.isFavorite(doc.id) }
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showShare) { ShareSheet(activityItems: shareItems) }
        .sheet(isPresented: $showEdit) {
            EditDocumentSheet(doc: live) { updated in Task { await documentService.update(updated) } }
        }
        .confirmationDialog("Delete \"\(live.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await documentService.delete(live); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the file and cannot be undone.")
        }
        .alert(calendarAlertTitle, isPresented: Binding(
            get: { calendarOutcome != nil },
            set: { if !$0 { calendarOutcome = nil } })) {
            if calendarOutcome == .denied {
                Button("doc_cal_open_settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(calendarAlertMessage)
        }
    }

    private var calendarAlertTitle: LocalizedStringKey {
        switch calendarOutcome {
        case .added:  return "doc_cal_added_title"
        case .denied: return "doc_cal_denied_title"
        case .failed: return "doc_cal_failed_title"
        case .none:   return ""
        }
    }

    private var calendarAlertMessage: LocalizedStringKey {
        switch calendarOutcome {
        case .added:  return "doc_cal_added_msg"
        case .denied: return "doc_cal_denied_msg"
        case .failed: return "doc_cal_failed_msg"
        case .none:   return ""
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 92, height: 92)
                    .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: tint.opacity(0.45), radius: 16, y: 8)
                Image(systemName: live.categoryIcon)
                    .font(AppFont.scaled(36, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(live.name)
                .font(AppFont.scaled(23, weight: .bold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                Text(LocalizedStringKey(live.category.capitalized))
                    .font(AppFont.caption).foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, AppSpacing.xxs)
                    .background(.white.opacity(0.14), in: Capsule())
                if live.isCritical {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill").font(AppFont.scaled(10))
                        Text("Critical").font(AppFont.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, AppSpacing.xxs)
                    .background(.red.opacity(0.5), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RadialGradient(colors: [.white.opacity(0.16), .clear],
                                        center: .top, startRadius: 6, endRadius: 200))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
        )
        .shadow(color: tint.opacity(0.25), radius: 20, y: 10)
    }

    // MARK: File card + primary actions

    private var fileCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: fileGlyph).font(AppFont.scaled(22)).foregroundStyle(tint).frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(live.fileName).font(AppFont.footnoteEmphasis).foregroundStyle(.primary).lineLimit(1)
                        Text(live.fileSizeDisplay.isEmpty ? (live.mimeType ?? "File") : live.fileSizeDisplay)
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    actionButton("Open", "arrow.up.forward.square", tint: .accentColor) { open() }
                    actionButton("Share", "square.and.arrow.up", tint: .primary) { share() }
                }
            }
        }
    }

    // MARK: Rich record (D1) — only the populated fields render

    private var richDetailsCard: some View {
        // Build each group's non-empty rows, then only show groups that have any.
        let dateRows: [(String, LocalizedStringKey, String)] = [
            ("calendar.badge.plus", "doc_f_issued", live.issuedAt.flatMap(displayDate) ?? ""),
            ("arrow.triangle.2.circlepath", "doc_f_renew", live.renewAt.flatMap(displayDate) ?? ""),
            ("bell", "doc_f_notify", live.notifyAt.flatMap(displayDate) ?? ""),
        ].filter { !$0.2.isEmpty }

        let issuerRows: [(String, LocalizedStringKey, String)] = [
            ("building.2", "doc_f_company", live.issuerCompany ?? ""),
            ("person", "doc_f_contact", live.issuerContact ?? ""),
            ("phone", "doc_f_phone", live.issuerPhone ?? ""),
            ("envelope", "doc_f_email", live.issuerEmail ?? ""),
            ("globe", "doc_f_website", live.issuerWebsite ?? ""),
            ("person.text.rectangle", "doc_f_client_number", live.clientNumber ?? ""),
        ].filter { !$0.2.isEmpty }

        let idRows: [(String, LocalizedStringKey, String)] = [
            ("number", "doc_f_number", live.docNumber ?? ""),
            ("number", "doc_f_series", live.series ?? ""),
            ("doc.text", "doc_f_contract_code", live.contractCode ?? ""),
            ("person.text.rectangle", "doc_f_client_code", live.clientCode ?? ""),
            ("building.columns", "doc_f_fiscal_code", live.fiscalCode ?? ""),
            ("shield", "doc_f_policy", live.policyNumber ?? ""),
            ("barcode", "doc_f_barcode", live.barcode ?? ""),
        ].filter { !$0.2.isEmpty }

        return VStack(spacing: 16) {
            if let sub = live.subcategory, !sub.isEmpty {
                infoGroup("doc_sec_classification", "tag.fill", .purple, [
                    ("square.grid.2x2", "doc_f_subcategory", sub),
                ])
            }
            if !dateRows.isEmpty { infoGroup("doc_sec_dates", "calendar", .orange, dateRows) }
            calendarActions
            if !issuerRows.isEmpty { infoGroup("doc_sec_issuer", "building.2.fill", .blue, issuerRows) }
            if !idRows.isEmpty { infoGroup("doc_sec_identifiers", "number", .teal, idRows) }
            financialGroup
        }
    }

    @ViewBuilder
    private var financialGroup: some View {
        let rows = financialRows
        if !rows.isEmpty { infoGroup("doc_sec_financial", "creditcard.fill", .green, rows) }
    }

    private var financialRows: [(String, LocalizedStringKey, String)] {
        guard let value = live.value else { return [] }
        var rows: [(String, LocalizedStringKey, String)] = [
            ("banknote", "doc_f_value", CurrencyService.money(value, code: live.currency ?? "RON", whole: false)),
        ]
        if let vat = live.vat {
            let n = vat.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(vat)) : String(format: "%.1f", vat)
            rows.append(("percent", "doc_f_vat", "\(n)%"))
        }
        if let rec = live.recurrence, rec != "one-off" {
            rows.append(("arrow.triangle.2.circlepath", "doc_f_recurrence", DocRecurrence.text(rec)))
        }
        return rows
    }

    // MARK: Calendar actions (D5) — add a renewal/expiry event via EventKit

    private enum CalKind { case renewal, expiry }

    enum CalendarOutcome: Identifiable {
        case added, denied, failed
        var id: Int { hashValue }
    }

    /// Buttons offered only for dates the document actually has. Each creates a
    /// real EventKit event on that date (with an alarm), gated on live
    /// authorization; denial is surfaced, never a false success.
    @ViewBuilder
    private var calendarActions: some View {
        let renew  = live.renewAt.flatMap { AppDate.day(from: $0) }
        let expiry = live.expiresAt.flatMap { AppDate.day(from: $0) }
        if renew != nil || expiry != nil {
            VStack(spacing: 8) {
                if let renew {
                    calendarButton("doc_cal_add_renewal", date: renew, kind: .renewal)
                }
                if let expiry {
                    calendarButton("doc_cal_add_expiry", date: expiry, kind: .expiry)
                }
            }
        }
    }

    private func calendarButton(_ title: LocalizedStringKey, date: Date, kind: CalKind) -> some View {
        Button { addToCalendar(date: date, kind: kind) } label: {
            HStack(spacing: 10) {
                if isAddingToCalendar { ProgressView().scaleEffect(0.8) }
                else { Image(systemName: "calendar.badge.plus").font(AppFont.footnoteEmphasis) }
                Text(title).font(AppFont.footnoteEmphasis)
                Spacer()
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .background(Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isAddingToCalendar)
    }

    private func addToCalendar(date: Date, kind: CalKind) {
        HapticFeedback.selection()
        isAddingToCalendar = true
        Task { @MainActor in
            defer { isAddingToCalendar = false }
            // Reuse the app's one EventKit path (TaskCalendarSync): request
            // access exactly as tasks do; only proceed on a real grant.
            let access = await TaskCalendarSync.requestEventAccess()
            guard access != .denied else {
                calendarOutcome = .denied
                HapticFeedback.error()
                return
            }
            let format = kind == .renewal
                ? String(localized: "doc_cal_renewal_title")
                : String(localized: "doc_cal_expiry_title")
            let notes = String(localized: "doc_cal_event_notes")
            // calendarId nil → the store's default calendar, which works for
            // both full and write-only access.
            let ok = TaskCalendarSync.addEvent(title: String(format: format, live.name),
                                               notes: notes, date: date,
                                               hasTime: false, calendarId: nil)
            calendarOutcome = ok ? .added : .failed
            ok ? HapticFeedback.success() : HapticFeedback.error()
        }
    }

    private func infoGroup(_ title: LocalizedStringKey, _ icon: String, _ color: Color,
                           _ rows: [(String, LocalizedStringKey, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(color)
                Text(title).font(AppFont.captionStrong).textCase(.uppercase).foregroundStyle(.secondary)
            }
            .padding(.leading, AppSpacing.sm)
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                        if idx > 0 { div }
                        row(r.0, r.1, r.2)
                    }
                }
            }
        }
    }

    private func displayDate(_ iso: String) -> String? {
        guard let d = AppDate.day(from: iso) else { return iso }
        return AppDate.monthDayYear.string(from: d)
    }

    private var detailsCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                if let expiry = live.expiresDisplay {
                    row("calendar", "Expires", expiry, color: live.isExpiringSoon ? .orange : Color.primary.opacity(0.55)); div
                }
                if !live.sharedMemberIds.isEmpty {
                    row("person.2.fill", "Shared with", "\(live.sharedMemberIds.count)"); div
                }
                if let desc = live.description, !desc.isEmpty {
                    row("text.alignleft", "Notes", desc); div
                }
                row("clock", "Added", formattedCreated)
                if !live.tags.isEmpty {
                    div
                    HStack {
                        Image(systemName: "tag.fill").font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 28)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(live.tags, id: \.self) { t in
                                    Text(t).font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.7))
                                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.08), in: Capsule())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                }
                div
                Button(role: .destructive) { HapticFeedback.warning(); showDeleteConfirm = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").font(AppFont.scaled(13)).frame(width: 28)
                        Text("Delete document").font(AppFont.scaled(14))
                        Spacer()
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showEdit = true } label: {
                Text("Edit").font(AppFont.footnoteEmphasis).foregroundStyle(Color.accentColor)
                    .padding(.horizontal, AppSpacing.md).padding(.vertical, 6)
            }
            .padding(6)
        }
    }

    // MARK: Bits

    private func row(_ icon: String, _ label: LocalizedStringKey, _ value: String, color: Color = Color.primary.opacity(0.55)) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.4)).frame(width: 28)
            Text(label).font(AppFont.scaled(14)).foregroundStyle(.primary)
            Spacer()
            Text(value).font(AppFont.scaled(13)).foregroundStyle(color).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
    }

    private var div: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

    private func actionButton(_ title: LocalizedStringKey, _ icon: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppFont.footnoteEmphasis).foregroundStyle(tint)
                .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.md)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var fileGlyph: String {
        if live.mimeType == "application/pdf" { return "doc.richtext.fill" }
        if live.mimeType?.hasPrefix("image/") == true { return "photo.fill" }
        return "doc.fill"
    }

    private var formattedCreated: String {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: live.createdAt) ?? ISO8601DateFormatter.withFractional.date(from: live.createdAt) {
            return d.formatted(date: .abbreviated, time: .omitted)
        }
        return String(live.createdAt.prefix(10))
    }

    private func open() {
        guard let url = URL(string: live.fileUrl) else { return }
        // History (D5): opening the primary file is the honest "viewed" moment.
        Task { await DocumentEventsService.log(documentId: live.id, kind: .viewed) }
        if live.mimeType == "application/pdf" || live.mimeType?.hasPrefix("image/") == true {
            Task {
                if let data = try? Data(contentsOf: url) {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(live.fileName)
                    try? data.write(to: tmp)
                    await MainActor.run { previewURL = tmp }
                } else { await UIApplication.shared.open(url) }
            }
        } else { UIApplication.shared.open(url) }
    }

    private func share() {
        guard let url = URL(string: live.fileUrl) else { return }
        Task {
            if let data = try? Data(contentsOf: url) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(live.fileName)
                try? data.write(to: tmp)
                await MainActor.run { shareItems = [tmp]; showShare = true }
            } else {
                await MainActor.run { shareItems = [url]; showShare = true }
            }
        }
    }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Edit document metadata

struct EditDocumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: String
    @State private var fields: DocumentFieldState
    private let original: DocumentModel
    let onSave: (DocumentModel) -> Void

    private let categories = ["contract", "legal", "warranty", "insurance", "certificate",
                              "manual", "invoice", "permit", "tax", "utility", "photo", "other"]

    init(doc: DocumentModel, onSave: @escaping (DocumentModel) -> Void) {
        self.original = doc
        self.onSave = onSave
        _name = State(initialValue: doc.name)
        _category = State(initialValue: doc.category)
        _fields = State(initialValue: DocumentFieldState(seed: doc))
    }

    var body: some View {
        FormScaffold(title: "Edit document",
                     canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                     isSaving: false, error: .constant(nil),
                     onSave: { save() }) {
            FormGroup {
                FormRow(icon: "doc.text.fill") {
                    TextField("Name", text: $name)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        .autocorrectionDisabled()
                }
            }
            FormGroup {
                HStack(spacing: 12) {
                    Image(systemName: "tag.fill").font(AppFont.scaled(14)).foregroundStyle(.purple).frame(width: 22)
                    Text("Category").font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: $category) {
                        ForEach(categories, id: \.self) { Text(LocalizedStringKey($0.capitalized)).tag($0) }
                    }
                    .tint(Color.primary.opacity(AppOpacity.emphasis))
                }
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
            }
            ForEach(DocumentCategorySchema.sections(for: category)) { section in
                DocSectionView(section: section, state: fields)
            }
        }
    }

    private func save() {
        let typedTag = fields.string(.tags).trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedTag.isEmpty, !fields.tags.contains(typedTag) { fields.tags.append(typedTag) }
        var updated = fields.apply(to: original)
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.category = category
        onSave(updated)
        HapticFeedback.success()
        dismiss()
    }
}
