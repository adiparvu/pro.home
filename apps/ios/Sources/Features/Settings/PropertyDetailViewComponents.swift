import SwiftUI
import PhotosUI

// MARK: - PropertyDetailView sections

extension PropertyDetailView {

    /// Coordinate space of the page's scroll view — the stretchy hero
    /// measures itself in it (rest minY == 0 at the top of the screen).
    private static let heroScrollSpace = "propertyDetailHeroScroll"
    private static let heroHeight: CGFloat = 280
    /// The inline-title strip at the bottom of the compact bar — the iPhone
    /// navigation-bar band the floating buttons sit in.
    private static let compactBarStripHeight: CGFloat = 44
    /// Estimated distance from the hero's bottom edge to the top of the
    /// page-title text: content column top padding (`AppSpacing.lg`) +
    /// `PageHeader` top padding (`AppSpacing.sm`) + the kicker line
    /// (~15pt at default Dynamic Type).
    private static let heroTitleTopGap: CGFloat = 39
    /// Scroll distance over which the compact bar fades in, starting the
    /// moment the title's top edge slides under the bar's bottom edge.
    private static let heroBarFadeDistance: CGFloat = 28

    @ViewBuilder
    func mainContent(_ property: PropertyModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                photoHeader(property)

                VStack(spacing: 16) {
                    PageHeader(
                        title: property.name,
                        subtitle: property.propertyType
                    )

                    basicCard(property)

                    if let story = property.story, !story.isEmpty {
                        storyCard(story)
                    }

                    if let renovations = property.renovations, !renovations.isEmpty {
                        renovationsCard(renovations)
                    }

                    if let owners = property.owners, !owners.isEmpty {
                        ownersCard(owners)
                    }

                    plansButton

                    PropertyInsightsSections(propertyId: property.id)

                    // Documents · works timeline · house team · passport —
                    // shown on the active property (their services are
                    // active-property-scoped; see PropertyDetailSections).
                    PropertyDetailExtraSections(property: property)

                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .coordinateSpace(name: Self.heroScrollSpace)
        .background(appBackground.ignoresSafeArea())
        // Edge-to-edge hero: the scroll content starts at the very top of
        // the screen, under the status bar and the floating nav buttons.
        .ignoresSafeArea(edges: .top)
        // Measured OUTSIDE the ignored edge, so it still reports the full
        // status-bar + navigation-bar height — the compact bar's frame.
        //
        // LOOP GUARD: this callback runs mid-layout, and with a hidden bar
        // background + a top-ignoring ScrollView the measured inset is
        // recomputed while the navigation bar settles during the push. A
        // synchronous @State write from inside that measurement re-enters
        // the same layout pass — if the inset flips between passes the page
        // livelocks on the main thread (freeze → watchdog kill). Absorb
        // sub-point jitter with a dead-band and land the write in its own
        // main-queue turn, so every re-layout is frame-paced, never
        // same-pass re-entrant.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { inset in
            guard abs(inset - heroTopInset) > 0.5 else { return }
            Task { @MainActor in
                if abs(inset - heroTopInset) > 0.5 { heroTopInset = inset }
            }
        }
        .overlay(alignment: .top) { compactBar(property) }
        .onPreferenceChange(StretchyHeroBottomEdgeKey.self) { bottom in
            updateHeroBarProgress(heroBottom: bottom)
        }
    }

    // MARK: Photo header

    @ViewBuilder
    private func photoHeader(_ property: PropertyModel) -> some View {
        StretchyHeroHeader(height: Self.heroHeight,
                           scrollSpace: Self.heroScrollSpace) {
            heroMedia(property)
        } overlay: {
            heroControls
        }
    }

    /// The stretchable photo layer. The hero sizes, clips, stretches,
    /// recedes and dims it — keep it free of controls.
    @ViewBuilder
    private func heroMedia(_ property: PropertyModel) -> some View {
        Group {
            if let urlStr = property.photoUrl, let url = URL(string: urlStr) {
                StorageImage(url: url, targetSize: 520) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        photoPlaceholder
                    }
                }
            } else {
                photoPlaceholder
            }
        }
        .overlay(alignment: .top) {
            // Keeps the status bar and floating buttons legible over bright
            // skies; pinned to the photo's visual top, so it stays at the
            // screen top while the hero is stretched.
            LinearGradient(colors: [.black.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .allowsHitTesting(false)
        }
    }

    /// Controls pinned to the hero's resting bounds — never stretched,
    /// receded, or dimmed.
    private var heroControls: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [.clear, Color(uiColor: .systemBackground).opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            Group {
                if isUploadingPhoto {
                    ProgressView()
                        .tint(.white)
                        .padding(AppSpacing.md)
                        .glassCircle()
                } else {
                    Button { showPhotoMenu = true } label: {
                        Image(systemName: "camera.fill")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.white)
                            .padding(AppSpacing.md)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                    .accessibilityLabel("Change photo")
                }
            }
            .padding(AppSpacing.lg)
        }
    }

    // MARK: Compact inline bar

    /// The TestFlight transition: once the page title would slide under the
    /// top, a thin-material bar materializes with the property name inline.
    /// The system's floating back/edit buttons draw above it, visually
    /// settling into the bar. Decorative only — never intercepts touches,
    /// hidden from accessibility (the page title remains in the content).
    private func compactBar(_ property: PropertyModel) -> some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.bar)
            Text(property.name)
                .font(AppFont.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                // Clearance for the floating back/edit buttons on top.
                .padding(.horizontal, 72)
                .frame(height: Self.compactBarStripHeight)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 0.5)
        }
        .frame(height: heroTopInset)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .opacity(heroBarProgress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Single source of truth for the bar fade, fed by the hero's
    /// layout-derived bottom edge. State is written only when the derived
    /// progress actually changes (quantized), so scrolling outside the fade
    /// window never invalidates the page.
    func updateHeroBarProgress(heroBottom: CGFloat) {
        // Without a measured top inset the bar has no frame to occupy —
        // keep it hidden rather than float a stray title.
        guard heroTopInset > 0 else {
            if heroBarProgress != 0 {
                Task { @MainActor in
                    if heroBarProgress != 0 { heroBarProgress = 0 }
                }
            }
            return
        }
        let titleTop = heroBottom + Self.heroTitleTopGap
        let raw = (heroTopInset - titleTop) / Self.heroBarFadeDistance
        let clamped = min(max(raw, 0), 1)
        // Reduce Motion: an instant step at the midpoint instead of a fade.
        let next = reduceMotion
            ? (clamped < 0.5 ? 0 : 1)
            : (clamped * 50).rounded() / 50
        guard next != heroBarProgress else { return }
        // Same transaction-break as the inset capture above: the preference
        // is collected during view updates, so its handler must never write
        // state back into the pass that produced it. The bar fade lands one
        // frame later — invisible across a 28 pt fade window — and a
        // geometry↔state oscillation can no longer lock the main thread.
        Task { @MainActor in
            if heroBarProgress != next { heroBarProgress = next }
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.65), .indigo.opacity(0.5), .purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "house.fill")
                .font(AppFont.scaled(72, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    // MARK: Basic details card

    private func basicCard(_ property: PropertyModel) -> some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                addressRow(property)
                rowDivider()
                if !property.country.isEmpty {
                    row("globe.europe.africa.fill", "Country", property.country, .blue)
                    rowDivider()
                }
                // `Int(Double)` traps on values outside Int's range — a
                // garbage `size_sqm` row must degrade, never kill the page.
                if let size = property.sizeSqm, size.isFinite, size > 0 {
                    row("ruler.fill", "Area", "\(Int(min(size.rounded(), 100_000_000))) m²", .orange)
                    rowDivider()
                }
                if let rooms = property.numRooms {
                    row("door.left.hand.open", "Rooms", "\(rooms)", .green)
                    rowDivider()
                }
                if let year = property.yearBuilt {
                    row("calendar.badge.clock", "Year built", "\(year)", .indigo)
                    rowDivider()
                }
                if let score = property.healthScore {
                    healthRow(property, score: score)
                    rowDivider()
                }
                if let lat = property.latitude, let lon = property.longitude {
                    // The raw numbers became a live map: a cached MapKit
                    // snapshot with the pin on the property; the compact
                    // coordinates caption stays underneath. Tap → the same
                    // navigation menu as the address.
                    PropertyMapSnapshotCard(latitude: lat, longitude: lon,
                                            title: property.name)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.md)
                }
            }
        }
    }

    /// Adresă, alive: tap opens a menu — directions in Hărți / Google Maps /
    /// Waze (only when the property has real coordinates) plus copy. Without
    /// coordinates only the copy action appears; nothing pretends to navigate.
    private func addressRow(_ property: PropertyModel) -> some View {
        let address = "\(property.addressLine1), \(property.city)"
        return Menu {
            if let lat = property.latitude, let lon = property.longitude {
                ForEach(NavigationAppLauncher.availableOptions()) { opt in
                    Button {
                        NavigationAppLauncher.open(opt.id, lat: lat, lon: lon,
                                                   label: property.name)
                    } label: {
                        Label {
                            Text(verbatim: String(format: String(localized: "prop_detail_open_in_fmt"),
                                                  opt.label))
                        } icon: {
                            Image(systemName: "arrow.triangle.turn.up.right.circle")
                        }
                    }
                }
            }
            Button {
                UIPasteboard.general.string = address
                HapticFeedback.success()
            } label: {
                Label("prop_detail_copy_address", systemImage: "doc.on.doc")
            }
        } label: {
            // "mappin.fill" is NOT a real SF Symbol — it rendered as an
            // empty square (IMG_8646). The address pin glyph is this one.
            row("mappin.and.ellipse", "Address", address, .blue, chevron: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Address")
        .accessibilityValue(Text(verbatim: address))
    }

    /// Scor de sănătate, alive: on the active property it opens the existing
    /// health dashboard (whose element data is active-property-scoped);
    /// on other homes it stays an honest static row.
    @ViewBuilder
    private func healthRow(_ property: PropertyModel, score: Int) -> some View {
        let color: Color = score >= 70 ? .green : score >= 40 ? .orange : .red
        if property.id == propertyService.primary?.id {
            Button {
                showHealthDashboard = true
                HapticFeedback.impact(.light)
            } label: {
                row("heart.fill", "Health score", "\(score)/100", color, chevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Health score")
            .accessibilityHint(Text("prop_detail_health_hint"))
        } else {
            row("heart.fill", "Health score", "\(score)/100", color)
        }
    }

    private func row(_ icon: String, _ label: LocalizedStringKey, _ value: String,
                     _ color: Color, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .glassRoundedRect(AppRadius.sm)
            Text(label)
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
            Text(value)
                .font(AppFont.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }

    private func rowDivider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }

    // MARK: Story

    private func storyCard(_ story: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Story", systemImage: "text.quote")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Text(story)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Renovations timeline

    private func renovationsCard(_ renovations: [Renovation]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Renovations", systemImage: "wrench.and.screwdriver.fill")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(renovations.enumerated()), id: \.element.id) { idx, r in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 10, height: 10)
                                    .padding(.top, AppSpacing.xxs)
                                if idx < renovations.count - 1 {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.2))
                                        .frame(width: 2, height: 32)
                                }
                            }
                            .frame(width: 10)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.title)
                                    .font(AppFont.footnoteEmphasis)
                                Text(r.yearRange)
                                    .font(AppFont.scaled(12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, idx < renovations.count - 1 ? 22 : 0)

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: Owners history

    private func ownersCard(_ owners: [OwnerRecord]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Owners", systemImage: "person.2.fill")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                VStack(spacing: 0) {
                    ForEach(Array(owners.enumerated()), id: \.element.id) { idx, owner in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "person.fill")
                                        .font(AppFont.scaled(14))
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(owner.name)
                                        .font(AppFont.footnoteEmphasis)
                                    Text(owner.yearRange)
                                        .font(AppFont.scaled(12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, AppSpacing.sm)
                            if idx < owners.count - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.05))
                                    .frame(height: 0.5)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Plans

    private var plansButton: some View {
        NavigationLink {
            BlueprintsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext.fill")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.orange)
                    .frame(width: 36, height: 36)
                    .glassRoundedRect(10)
                Text("Property plans")
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(AppSpacing.lg)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - Camera picker

struct PropertyCameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PropertyCameraPickerView
        init(_ parent: PropertyCameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
