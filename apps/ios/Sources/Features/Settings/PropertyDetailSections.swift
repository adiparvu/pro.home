import SwiftUI
import MapKit

// MARK: - Property detail: live map card + the house's living sections
//
// Everything below is fed by data the app already holds — documents linked
// to this property (documents.property_id), the service log (financial
// records tagged "service"), journal photos (photo_journal per property) and
// the contractors roster. The honesty law applies throughout: a section with
// nothing real to show renders nothing.
//
// Documents, works, team and passport read the app-wide services, which are
// scoped to the ACTIVE property — so those sections only render on the
// active property's page. Rendering them on a second home would show the
// wrong house's data or a false "empty".

// MARK: - Map snapshot cache

/// One snapshot per (coordinate, appearance): generated once by
/// MKMapSnapshotter on its own background machinery, kept in an NSCache and
/// reused across pushes of the page. No live map view, no continuous work.
enum PropertyMapSnapshotCache {
    private static let cache = NSCache<NSString, UIImage>()
    /// Rendered size — fixed so the cache key never churns with layout.
    static let size = CGSize(width: 700, height: 300)

    static func key(latitude: Double, longitude: Double, dark: Bool) -> String {
        String(format: "%.5f,%.5f,%@", latitude, longitude, dark ? "dark" : "light")
    }

    static func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    @MainActor
    static func snapshot(latitude: Double, longitude: Double, dark: Bool) async -> UIImage? {
        let key = key(latitude: latitude, longitude: longitude, dark: dark)
        if let hit = cached(key) { return hit }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)

        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }
        cache.setObject(snap.image, forKey: key as NSString)
        return snap.image
    }
}

// MARK: - Map snapshot card (the Coordonate row, alive)

struct PropertyMapSnapshotCard: View {
    let latitude: Double
    let longitude: Double
    /// Names the destination pin in the navigation apps.
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var snapshot: UIImage?

    private var cacheKey: String {
        PropertyMapSnapshotCache.key(latitude: latitude, longitude: longitude,
                                     dark: colorScheme == .dark)
    }

    var body: some View {
        Menu {
            ForEach(NavigationAppLauncher.availableOptions()) { opt in
                Button {
                    NavigationAppLauncher.open(opt.id, lat: latitude, lon: longitude,
                                               label: title)
                } label: {
                    Label {
                        Text(verbatim: String(format: String(localized: "prop_detail_open_in_fmt"),
                                              opt.label))
                    } icon: {
                        Image(systemName: "arrow.triangle.turn.up.right.circle")
                    }
                }
            }
            Button {
                UIPasteboard.general.string = String(format: "%.5f, %.5f", latitude, longitude)
                HapticFeedback.success()
            } label: {
                Label("prop_detail_copy_coords", systemImage: "doc.on.doc")
            }
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if let snapshot {
                        Image(uiImage: snapshot)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.primary.opacity(AppOpacity.subtleFill))
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay {
                    // The snapshot is centered on the property, so the pin
                    // marks the exact coordinate. Hidden with the placeholder
                    // — a pin on grey would point at nothing.
                    if snapshot != nil {
                        Image(systemName: "mappin.circle.fill")
                            .font(AppFont.scaled(26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.brandDanger)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(AppFont.scaled(10))
                        .foregroundStyle(.teal)
                    Text("Coordinates")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                    Spacer()
                    Text(verbatim: String(format: "%.4f, %.4f", latitude, longitude))
                        .font(AppFont.scaled(11))
                        .monospacedDigit()
                        .foregroundStyle(Color.secondaryTextColor)
                }
                .padding(.top, AppSpacing.sm)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Coordinates")
        // Regenerates only when the coordinate or appearance actually changes.
        .task(id: cacheKey) {
            snapshot = PropertyMapSnapshotCache.cached(cacheKey)
            if snapshot == nil {
                snapshot = await PropertyMapSnapshotCache.snapshot(
                    latitude: latitude, longitude: longitude, dark: colorScheme == .dark)
            }
        }
    }
}

// MARK: - The extra sections (documents · works · team · passport)

struct PropertyDetailExtraSections: View {
    let property: PropertyModel

    @Environment(PropertyService.self) private var propertyService
    @Environment(DocumentService.self) private var documentService
    @Environment(FinancialService.self) private var financialService
    @Environment(ContractorService.self) private var contractorService
    @State private var journal = PhotoJournalService()
    @State private var showPassport = false

    /// The app-wide services hold the ACTIVE property's data — see the
    /// header note. Everything below is gated on this.
    private var isActiveProperty: Bool { property.id == propertyService.primary?.id }

    var body: some View {
        if isActiveProperty {
            documentsCard
            worksCard
            teamCard
            guidesCard
            passportRow
        }
    }

    // MARK: - House manual ("Manualul casei")

    /// The written knowledge of the home — one door into the manual, next
    /// to the passport it complements.
    private var guidesCard: some View {
        NavigationLink {
            HouseGuidesView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.brandPrimaryBlue)
                    .frame(width: 36, height: 36)
                    .glassRoundedRect(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("guides_title")
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                    Text("guides_card_subtitle")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(AppSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 18)
    }

    // MARK: Loading

    private func loadAll() async {
        // The journal instance is ours; the shared services only load when
        // still empty (they are usually warm from the rest of the app).
        async let photos: Void = journal.load(propertyId: property.id)
        if documentService.documents.isEmpty { await documentService.load() }
        if financialService.records.isEmpty { await financialService.load() }
        if contractorService.contractors.isEmpty { await contractorService.load() }
        _ = await photos
    }

    // MARK: - Documents ("Actele casei" + scadențe)

    private var propertyDocs: [DocumentModel] {
        documentService.documents.filter { $0.propertyId == property.id }
    }

    /// Dated documents, soonest deadline first (expired ones lead — they are
    /// the most urgent truth of all).
    private var deadlineDocs: [DocumentModel] {
        propertyDocs
            .filter { $0.daysUntilExpiry != nil }
            .sorted { ($0.expiresAt ?? "") < ($1.expiresAt ?? "") }
    }

    private var expiringSoonCount: Int {
        deadlineDocs.filter { ($0.daysUntilExpiry ?? .max) < 30 }.count
    }

    @ViewBuilder
    private var documentsCard: some View {
        // task on the always-present outer group so loading happens once,
        // whether or not the cards have content yet.
        let docs = propertyDocs
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink {
                    DocumentsView()
                        .environment(documentService)
                        .environment(propertyService)
                } label: {
                    HStack {
                        Label("Documents", systemImage: "doc.text.fill")
                            .font(AppFont.label)
                            .foregroundStyle(.secondary)
                            .tracking(0.8)
                        Spacer()
                        if !docs.isEmpty {
                            Text(verbatim: "\(docs.count)")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(Color.secondaryTextColor)
                        }
                        Image(systemName: "chevron.right")
                            .font(AppFont.scaled(11, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.28))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if docs.isEmpty {
                    Text("prop_detail_docs_empty")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.secondaryTextColor)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(deadlineDocs.prefix(3).enumerated()), id: \.element.id) { idx, doc in
                            if idx > 0 { insetDivider }
                            documentRow(doc)
                        }
                    }

                    if expiringSoonCount > 0 {
                        NavigationLink {
                            DocumentsView(initialCategory: "Expiring")
                                .environment(documentService)
                                .environment(propertyService)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(AppFont.scaled(11))
                                Text(verbatim: String(format: String(localized: "%lld documents expiring soon"),
                                                      expiringSoonCount))
                                    .font(AppFont.captionEmphasis)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(AppFont.scaled(10, weight: .medium))
                            }
                            .foregroundStyle(Color.brandWarning)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(Color.brandWarning.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await loadAll() }
    }

    private func documentRow(_ doc: DocumentModel) -> some View {
        NavigationLink {
            DocumentDetailView(doc: doc)
                .environment(documentService)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: doc.categoryIcon)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.orange)
                    .frame(width: 30, height: 30)
                    .glassRoundedRect(AppRadius.sm)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: doc.name)
                        .font(AppFont.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(verbatim: DocumentTypeDisplay.name(doc.category))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                }
                Spacer()
                if let days = doc.daysUntilExpiry, let display = doc.expiresDisplay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: days < 0
                             ? String(localized: "Expired")
                             : String(format: String(localized: "Expires %@"), display))
                            .font(AppFont.scaled(11, weight: days < 30 ? .semibold : .regular))
                            .foregroundStyle(days < 0 ? Color.brandDanger
                                             : days < 30 ? Color.brandWarning
                                             : Color.secondaryTextColor)
                    }
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Works timeline ("Istoricul lucrărilor")

    private struct WorkEvent: Identifiable {
        enum Kind {
            case service(FinancialRecord)
            case journal(PhotoJournalEntry)
        }
        let id: UUID
        let date: Date
        let kind: Kind
    }

    /// Service-log expenses (records tagged "service" — the carnet the
    /// appliance service book writes) merged with dated journal photos,
    /// newest first. Only rows genuinely linked to THIS property.
    private var workEvents: [WorkEvent] {
        var events: [WorkEvent] = financialService.records.compactMap { record in
            guard record.propertyId == property.id,
                  record.tags.contains(ApplianceServiceLog.serviceTag),
                  let date = AppDate.day(from: record.date) else { return nil }
            return WorkEvent(id: record.id, date: date, kind: .service(record))
        }
        events += journal.entries.compactMap { entry in
            guard let date = entry.takenDate else { return nil }
            return WorkEvent(id: entry.id, date: date, kind: .journal(entry))
        }
        return events.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var worksCard: some View {
        let events = Array(workEvents.prefix(4))
        if !events.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink {
                        ActivityFeedView()
                    } label: {
                        HStack {
                            Label("prop_detail_works_title", systemImage: "hammer.fill")
                                .font(AppFont.label)
                                .foregroundStyle(.secondary)
                                .tracking(0.8)
                            Spacer()
                            Text("prop_detail_see_all")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(Color.accentColor)
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(10, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                            workRow(event, isLast: idx == events.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func workRow(_ event: WorkEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(eventTint(event))
                    .frame(width: 9, height: 9)
                    .padding(.top, AppSpacing.xxs)
                if !isLast {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 2, height: 40)
                }
            }
            .frame(width: 10)

            switch event.kind {
            case .service(let record):
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: record.title)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(verbatim: "\(AppDate.monthYear.string(from: event.date).capitalized) · "
                         + CurrencyService.money(record.amount, code: record.currency, whole: true))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor)
                }
                .padding(.bottom, isLast ? 0 : 18)
            case .journal(let entry):
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: entry.title)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(verbatim: AppDate.monthYear.string(from: event.date).capitalized)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    StorageImage(source: entry.photoUrl) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
                .padding(.bottom, isLast ? 0 : 18)
            }

            if case .service = event.kind { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .combine)
    }

    private func eventTint(_ event: WorkEvent) -> Color {
        switch event.kind {
        case .service: return .orange
        case .journal: return .blue
        }
    }

    // MARK: - House team ("Echipa casei")

    @ViewBuilder
    private var teamCard: some View {
        let team = contractorService.contractors
        if team.isEmpty {
            // No roster yet: a slim, honest affordance into the existing
            // contractors module (which owns the add flow).
            NavigationLink {
                ContractorsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.teal)
                        .frame(width: 36, height: 36)
                        .glassRoundedRect(10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("prop_detail_team_title")
                            .font(AppFont.body)
                            .foregroundStyle(.primary)
                        Text("No contractors yet")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    Text("Adaugă")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(AppSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidGlass(cornerRadius: 18)
        } else {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink {
                        ContractorsView()
                    } label: {
                        HStack {
                            Label("prop_detail_team_title", systemImage: "person.2.fill")
                                .font(AppFont.label)
                                .foregroundStyle(.secondary)
                                .tracking(0.8)
                            Spacer()
                            Text(verbatim: "\(team.count)")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(Color.secondaryTextColor)
                            Image(systemName: "chevron.right")
                                .font(AppFont.scaled(11, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.28))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 0) {
                        ForEach(Array(team.prefix(4).enumerated()), id: \.element.id) { idx, contractor in
                            if idx > 0 { insetDivider }
                            contractorRow(contractor)
                        }
                    }
                }
            }
        }
    }

    private func contractorRow(_ contractor: ContractorModel) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(AppOpacity.tintedFill))
                    .frame(width: 36, height: 36)
                Text(verbatim: Self.initials(contractor.name))
                    .font(AppFont.scaled(13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.teal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: contractor.name)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(verbatim: contractor.specialty)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
            if let phone = contractor.phone, !phone.isEmpty {
                Button {
                    call(phone)
                } label: {
                    Image(systemName: "phone.fill")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.brandSuccess)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .accessibilityLabel("Call contractor")
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
        .contextMenu {
            if let phone = contractor.phone, !phone.isEmpty {
                Button { call(phone) } label: {
                    Label("Call contractor", systemImage: "phone.fill")
                }
                Button {
                    UIPasteboard.general.string = phone
                    HapticFeedback.success()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        } preview: {
            contractorPreview(contractor)
        }
    }

    /// The app-standard long-press card, fed only saved fields.
    private func contractorPreview(_ contractor: ContractorModel) -> some View {
        var details: [PreviewCardDetail] = []
        if let phone = contractor.phone, !phone.isEmpty {
            details.append(PreviewCardDetail(icon: "phone.fill", value: Text(verbatim: phone)))
        }
        if let email = contractor.email, !email.isEmpty {
            details.append(PreviewCardDetail(icon: "envelope.fill", value: Text(verbatim: email)))
        }
        if let address = contractor.address, !address.isEmpty {
            details.append(PreviewCardDetail(icon: "mappin.and.ellipse", value: Text(verbatim: address)))
        }
        var chips: [PreviewCardChip] = []
        if let rating = contractor.rating, rating > 0 {
            chips.append(PreviewCardChip(icon: "star.fill",
                                         text: Text(verbatim: "\(rating)/5"),
                                         tint: .yellow))
        }
        return PreviewCard(title: Text(verbatim: contractor.name),
                           subtitle: Text(verbatim: contractor.specialty),
                           tint: .teal,
                           details: details,
                           chips: chips) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(AppOpacity.tintedFill))
                    .frame(width: 44, height: 44)
                Image(systemName: contractor.specialtyIcon)
                    .font(AppFont.scaled(17))
                    .foregroundStyle(.teal)
            }
        }
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        HapticFeedback.impact(.light)
        UIApplication.shared.open(url)
    }

    private static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    // MARK: - Passport ("Pașaportul proprietății")

    private var passportRow: some View {
        Button {
            showPassport = true
            HapticFeedback.impact(.light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext.fill")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.brandPrimaryBlue)
                    .frame(width: 36, height: 36)
                    .glassRoundedRect(10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("passport_title")
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                    Text("passport_sheet_note")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(AppFont.scaled(15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(AppSpacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 18)
        .accessibilityLabel(Text("passport_title"))
        .sheet(isPresented: $showPassport) {
            // All services it reads are injected app-wide by MainTabView.
            PropertyPassportSheet()
        }
    }

    // MARK: - Shared bits

    private var insetDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 42)
    }
}
