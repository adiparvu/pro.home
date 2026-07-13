// Unreferenced since tab 2 became Spațiile casei (user decision) — safe to delete in a cleanup pass.
import SwiftUI

// MARK: - Element inspector (Apple Maps-style card)
//
// The small card that slides up when a pin is tapped on the Digital Twin.
// Presented with detents (compact → medium → full) and background
// interaction, so the map stays touchable while the card is up — the same
// interaction model as a place card in Apple Maps. Deep dives (full detail
// page, edit form, new task) are launched from here.
//
// Wears the smart-home warm glass skin (SmartHomeChrome/SmartHomeTheme):
// blurred cover-photo backdrop, glass tiles, warm-white text, one amber
// accent — semantic colors (health, success, favorites, category hues)
// stay untouched.

struct ElementInspectorSheet: View {
    let element: PropertyElement
    var zoneName: String?
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(PropertyElementService.self) private var elementService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(DocumentService.self) private var documentService
    @Environment(TaskService.self) private var taskService
    @Environment(BlueprintService.self) private var blueprintService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    /// The glass tile shape shared by stats, notes and the 3D row.
    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius, style: .continuous)
    }

    @State private var showDetail = false
    @State private var showNewTask = false
    @State private var show3DViewer = false

    private var linkedScan: HomeScan? { blueprintService.scan(forElement: element.id) }
    private var linkable3DScans: [HomeScan] {
        blueprintService.scans.filter { $0.is3D && $0.elementId == nil }
    }

    /// Live copy — favorite toggles and edits should reflect immediately.
    private var current: PropertyElement {
        elementService.elements.first(where: { $0.id == element.id }) ?? element
    }

    var body: some View {
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    quickActions
                    statsRow
                    if linkedScan != nil || !linkable3DScans.isEmpty {
                        scanSection
                    }
                    if let notes = current.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
                    if let desc = current.description, !desc.isEmpty, current.notes?.isEmpty ?? true {
                        notesCard(desc)
                    }
                    Spacer(minLength: 24)
                }
                .padding(AppSpacing.xl)
            }
            .environment(\.colorScheme, .dark)
        }
        .sheet(isPresented: $showDetail) {
            PropertyElementDetailView(element: current)
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
                .environment(documentService)
                .environment(taskService)
        }
        .sheet(isPresented: $showNewTask) { AddTaskView() }
        .sheet(isPresented: $show3DViewer) {
            if let scan = linkedScan {
                QuickLookSheet(url: blueprintService.fileURL(scan.fileName), title: scan.name)
            }
        }
    }

    // MARK: - 3D model (Faza 4 — LiDAR scans linked to buildings)

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("3D MODEL")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.smartTextSecondary)
            if let scan = linkedScan {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "cube.transparent.fill", color: Color.brandPurple, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scan.name).font(AppFont.subheadline).foregroundStyle(Color.smartTextPrimary).lineLimit(1)
                        Text(scan.kindLabel).font(AppFont.scaled(12)).foregroundStyle(Color.smartTextSecondary)
                    }
                    Spacer()
                    Button {
                        HapticFeedback.impact(.light)
                        show3DViewer = true
                    } label: {
                        Text("View")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.smartAmber)
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, 7)
                            .glassCapsule()
                    }
                    .buttonStyle(.plain)
                    Menu {
                        Button(role: .destructive) {
                            blueprintService.linkScan(scan, toElement: nil)
                        } label: {
                            Label("Unlink", systemImage: "link.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(Color.smartTextPrimary)
                            .frame(width: 30, height: 30)
                            .background(Color.smartGlassFill, in: Circle())
                    }
                    .accessibilityLabel("More")
                }
                .padding(AppSpacing.base)
                .background {
                    tileShape.fill(.ultraThinMaterial)
                    tileShape.fill(Color.smartGlassFill)
                }
                .clipShape(tileShape)
            } else {
                Menu {
                    ForEach(linkable3DScans) { scan in
                        Button {
                            blueprintService.linkScan(scan, toElement: element.id)
                            HapticFeedback.success()
                        } label: {
                            Label(scan.name, systemImage: "cube.transparent")
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cube.transparent")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.brandPurple)
                        Text("Link a 3D scan")
                            .font(AppFont.footnote)
                            .foregroundStyle(Color.smartTextPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AppFont.label)
                            .foregroundStyle(Color.smartTextSecondary)
                    }
                    .padding(AppSpacing.base)
                    .background {
                        tileShape.fill(.ultraThinMaterial)
                        tileShape.fill(Color.smartGlassFill)
                    }
                    .clipShape(tileShape)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(current.name)
                    .font(AppFont.scaled(20, weight: .bold))
                    .foregroundStyle(Color.smartTextPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: current.elementType.icon).font(AppFont.scaled(11))
                    Text(current.elementType.displayName).font(AppFont.caption)
                    if let zoneName {
                        Text("·").font(AppFont.caption)
                        Text(zoneName).font(AppFont.caption).lineLimit(1)
                    }
                }
                .foregroundStyle(Color.smartTextSecondary)
            }
            Spacer()
            Button {
                HapticFeedback.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.smartTextPrimary)
                    .frame(width: 30, height: 30)
                    .background(Color.smartGlassFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let cover = current.coverPhotoUrl, let url = URL(string: cover) {
            StorageImage(url: url) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { current.elementType.accentColor.opacity(0.4) }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Image(systemName: current.elementType.icon)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(current.elementType.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Quick actions (round liquid-glass discs)

    private var quickActions: some View {
        HStack(spacing: 12) {
            inspectorActionBtn(icon: "doc.text.magnifyingglass", label: "Details", color: Color.smartAmber) {
                showDetail = true
            }
            inspectorActionBtn(icon: "pencil", label: "Edit", color: Color.smartAmber) {
                dismiss()
                onEdit()
            }
            inspectorActionBtn(icon: "checklist", label: "New task", color: Color.brandSuccess) {
                showNewTask = true
            }
            inspectorActionBtn(
                icon: current.isFavorite ? "star.fill" : "star",
                label: current.isFavorite ? "Favorite" : "Favorite",
                color: .yellow
            ) {
                Task { await elementService.toggleFavorite(elementId: current.id) }
            }
        }
    }

    private func inspectorActionBtn(icon: String, label: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppFont.title3)
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .glassCircle()
                Text(label)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.smartTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statTile(value: "\(current.healthScore)%", label: "Health",
                     icon: "heart.fill", color: current.healthColor)
            statTile(value: valueString, label: "Value",
                     icon: "banknote.fill", color: Color.brandSuccess)
            statTile(value: current.technicalCondition.displayName, label: "Condition",
                     icon: "wrench.and.screwdriver.fill", color: Color.smartAmber)
        }
    }

    private var valueString: String {
        guard let v = current.estimatedValue, v > 0 else { return "—" }
        return CurrencyService.money(v, code: appSettings.preferredCurrency, whole: true)
    }

    private func statTile(value: String, label: LocalizedStringKey, icon: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(AppFont.footnoteEmphasis).foregroundStyle(color)
            Text(value)
                .font(AppFont.scaled(15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.smartTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(AppFont.scaled(11)).foregroundStyle(Color.smartTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .background {
            tileShape.fill(.ultraThinMaterial)
            tileShape.fill(Color.smartGlassFill)
        }
        .clipShape(tileShape)
    }

    // MARK: - Notes

    private func notesCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.smartTextSecondary)
            Text(text)
                .font(AppFont.footnote)
                .foregroundStyle(Color.smartTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.base)
        .background {
            tileShape.fill(.ultraThinMaterial)
            tileShape.fill(Color.smartGlassFill)
        }
        .clipShape(tileShape)
    }
}
