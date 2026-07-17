import SwiftUI
import AVFoundation

// MARK: - Emergency Mode
//
// The page for the burst pipe at 2 AM: one screen with the numbers to call,
// where the shut-off valves are, the insurance papers, and a flashlight —
// zero navigation between you and the thing you need. This page is used IN
// PANIC, so the design rules invert: huge full-color tap targets, maximum
// contrast, no subtle elegance in the action path. Critical places are
// written by the household ahead of time (a picker over property elements
// would guess; the owner knows), and everything here works offline because
// contacts, notes, and photos live on the device.

struct EmergencyModeView: View {
    @Environment(DocumentService.self) private var documentService
    @Environment(AppRouter.self) private var router
    @Environment(PropertyService.self) private var propertyService
    @Environment(ProfileService.self) private var profileService
    @Environment(MessageService.self) private var messageService

    @State private var contacts: [EmergencyContact] = []
    @State private var notes: [EmergencyNote] = []
    @State private var placeImages: [UUID: UIImage] = [:]
    @State private var editingNote: EmergencyNote? = nil
    @State private var showAddNote = false
    @State private var showAddContact = false
    @State private var torchOn = false
    @State private var incidentPinned = false
    @State private var addressCopied = false
    @State private var photoItem: EmergencyPhotoItem? = nil
    @State private var activeGuide: EmergencyScenario? = nil

    // Family alert
    private enum FamilyAlertState: Equatable { case idle, sending, sent, failed }
    @State private var familyAlert: FamilyAlertState = .idle
    @State private var showAlertConfirm = false

    // Trusted emergency contact — the person TrustedContactView saved
    // (device-local, same @AppStorage keys it writes).
    @AppStorage("prvio.trustedContact.name")         private var trustedName: String = ""
    @AppStorage("prvio.trustedContact.phone")        private var trustedPhone: String = ""
    @AppStorage("prvio.trustedContact.relationship") private var trustedRelationship: String = ""

    // Editable gas number (per property, device-local)
    private static let defaultGasNumber = "0800-001122"
    @State private var gasNumber = EmergencyModeView.defaultGasNumber
    @State private var gasEditText = ""
    @State private var showGasEdit = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                callSection
                familyAlertCard
                torchCard
                islandPinCard
                guidesSection
                placesSection
                insuranceSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("emergency_title")
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: load)
        .onDisappear { setTorch(false) }
        .sheet(isPresented: $showAddContact) {
            AddEmergencyContactSheet { contact in
                contacts.append(contact)
                saveContacts()
            }
        }
        .sheet(isPresented: $showAddNote) {
            EmergencyNoteSheet { note, photoChange in
                notes.append(note)
                saveNotes()
                applyPhotoChange(photoChange, id: note.id)
            }
        }
        .sheet(item: $editingNote) { note in
            EmergencyNoteSheet(editing: note) { updated, photoChange in
                if let i = notes.firstIndex(where: { $0.id == updated.id }) {
                    notes[i] = updated
                    saveNotes()
                }
                applyPhotoChange(photoChange, id: updated.id)
            }
        }
        .sheet(item: $activeGuide) { scenario in
            EmergencyGuideSheet(scenario: scenario,
                                valvePlace: waterValvePlace,
                                valveImage: waterValvePlace.flatMap { placeImages[$0.id] })
        }
        .fullScreenCover(item: $photoItem) { item in
            EmergencyPhotoViewer(title: item.title, image: item.image)
        }
        .confirmationDialog("emg_alert_confirm_title", isPresented: $showAlertConfirm,
                            titleVisibility: .visible) {
            Button("emg_alert_confirm_send") { sendFamilyAlert() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("emg_alert_confirm_msg \(propertyService.primary?.name ?? "")")
        }
        .alert("emg_gas_edit_title", isPresented: $showGasEdit) {
            TextField(String(localized: "emg_gas_edit_ph"), text: $gasEditText)
                .keyboardType(.phonePad)
            Button("Save") { saveGasNumber() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("emg_gas_edit_msg")
        }
    }

    // MARK: Call — huge, full-color cards; tap anywhere dials
    //
    // 112 leads, the property address follows immediately (the dispatcher's
    // first question, and the one a blank mind can't answer), then gas and
    // the household's own numbers.

    private var callSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("emergency_call_header")
            VStack(spacing: 10) {
                emergencyCallCard(
                    title: Text(verbatim: "112"),
                    subtitle: Text("emergency_112_role"),
                    phone: "112",
                    fill: Color.brandDanger,
                    a11yName: "112"
                )
                addressCard
                gasCard
                trustedContactCard
                ForEach(contacts) { c in
                    customContactCard(c)
                }
                Button {
                    showAddContact = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Label("emergency_add_contact", systemImage: "plus")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.primary.opacity(AppOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A full-bleed colored call card: the whole surface dials.
    private func emergencyCallCard(title: Text, subtitle: Text, phone: String,
                                   fill: Color, a11yName: String) -> some View {
        Button {
            HapticFeedback.impact(.heavy)
            call(phone)
        } label: {
            HStack(spacing: AppSpacing.base) {
                VStack(alignment: .leading, spacing: 3) {
                    title
                        .font(AppFont.scaled(26, weight: .heavy, design: .rounded))
                    subtitle
                        .font(AppFont.footnoteEmphasis)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "phone.fill")
                    .font(AppFont.scaled(28, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("emergency_call_a11y \(a11yName)"))
    }

    /// Gas keeps the big-orange treatment plus a long-press to edit the
    /// number (0800-001122 is Romania's default; abroad it's different).
    private var gasCard: some View {
        Button {
            HapticFeedback.impact(.heavy)
            call(gasNumber)
        } label: {
            HStack(spacing: AppSpacing.base) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("emergency_gas_name")
                        .font(AppFont.scaled(22, weight: .heavy, design: .rounded))
                    Text(verbatim: gasNumber)
                        .font(AppFont.scaled(16, weight: .bold, design: .rounded))
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "phone.fill")
                    .font(AppFont.scaled(28, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.orange, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("emergency_call_a11y \(String(localized: "emergency_gas_name"))"))
        .contextMenu {
            Button {
                gasEditText = gasNumber
                showGasEdit = true
            } label: {
                Label("emg_gas_edit_title", systemImage: "pencil")
            }
        }
    }

    // MARK: Trusted contact — the person Settings → Trusted Contact saved
    //
    // Rendered ONLY when a contact actually exists (honest data: no
    // placeholder person). Same full-color, whole-surface-dials treatment as
    // the other call cards — purple, so it's never mistaken for 112 or gas.
    // Without a contact, a small quiet row routes toward Profile settings,
    // where TrustedContactView lives.

    @ViewBuilder
    private var trustedContactCard: some View {
        if !trustedName.isEmpty {
            Button {
                HapticFeedback.impact(.heavy)
                call(trustedPhone)
            } label: {
                HStack(spacing: AppSpacing.base) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(AppFont.scaled(30, weight: .semibold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trustedName)
                            .font(AppFont.scaled(22, weight: .heavy, design: .rounded))
                            .lineLimit(1)
                        Text(verbatim: trustedRelationship.isEmpty
                             ? String(localized: "emg_trusted_contact")
                             : "\(String(localized: "emg_trusted_contact")) · \(trustedRelationship)")
                            .font(AppFont.footnoteEmphasis)
                            .opacity(0.9)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "phone.fill")
                        .font(AppFont.scaled(28, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.lg)
                .frame(maxWidth: .infinity)
                .background(Color.brandPurple, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("emergency_call_a11y \(trustedName)"))
        } else {
            Button {
                HapticFeedback.impact(.light)
                router.navigate(to: .profile)
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "person.badge.shield.checkmark.fill", color: Color.brandSkyBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("emg_trusted_configure")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        Text("emg_trusted_configure_hint")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .accessibilityLabel(Text("emg_trusted_configure"))
        }
    }

    /// Household numbers get the same size at a neutral tint — big targets,
    /// but never mistaken for 112. Long-press to remove.
    private func customContactCard(_ c: EmergencyContact) -> some View {
        Button {
            HapticFeedback.impact(.heavy)
            call(c.phone)
        } label: {
            HStack(spacing: AppSpacing.base) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name)
                        .font(AppFont.scaled(22, weight: .heavy, design: .rounded))
                    Text(verbatim: c.role.isEmpty ? c.phone : "\(c.role) · \(c.phone)")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "phone.fill")
                    .font(AppFont.scaled(28, weight: .bold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(AppOpacity.tintedFill),
                        in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("emergency_call_a11y \(c.name)"))
        .contextMenu {
            Button(role: .destructive) {
                contacts.removeAll { $0.id == c.id }
                saveContacts()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Address — the dispatcher's first question
    //
    // Big and directly under 112, because "what's the address?" is exactly
    // the question a panicking mind goes blank on. Tap copies it.

    @ViewBuilder
    private var addressCard: some View {
        if let property = propertyService.primary {
            let address = [property.addressLine1, property.postalCode ?? "", property.city]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            Button {
                copyAddress(name: property.name, address: address)
            } label: {
                HStack(spacing: AppSpacing.base) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(property.name)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.secondary)
                        Text(verbatim: address)
                            .font(AppFont.scaled(19, weight: .bold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Text(addressCopied ? "emg_address_copied" : "emg_address_copy_hint")
                            .font(AppFont.caption)
                            .foregroundStyle(addressCopied ? Color.brandSuccess : .secondary)
                    }
                    Spacer()
                    Image(systemName: addressCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .font(AppFont.scaled(24, weight: .semibold))
                        .foregroundStyle(addressCopied ? Color.brandSuccess : .primary)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.lg)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidGlass(cornerRadius: AppRadius.xl)
            .accessibilityLabel(Text("emg_address_a11y \(property.name) \(address)"))
        }
    }

    private func copyAddress(name: String, address: String) {
        UIPasteboard.general.string = "\(name), \(address)"
        HapticFeedback.success()
        withAnimation(.snappy) { addressCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(AppMotion.state) { addressCopied = false }
        }
    }

    // MARK: Alert family — one tap, one confirmation
    //
    // Sends "⚠️ Emergency at <property> — call me!" to the family group chat;
    // the existing DB trigger fans it out as an instant push. The single
    // confirmation is deliberate: a pocket-tap false alarm here costs real
    // adrenaline in the whole household.

    @ViewBuilder
    private var familyAlertCard: some View {
        if propertyService.primary != nil {
            Button {
                guard familyAlert != .sending else { return }
                HapticFeedback.impact(.heavy)
                showAlertConfirm = true
            } label: {
                HStack(spacing: AppSpacing.base) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(familyAlert == .sent ? "emg_alert_sent" : "emg_alert_family")
                            .font(AppFont.scaled(20, weight: .bold))
                        Text(familyAlertSubtitle)
                            .font(AppFont.footnote)
                            .opacity(0.9)
                    }
                    Spacer()
                    if familyAlert == .sending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: familyAlert == .sent
                              ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                            .font(AppFont.scaled(28, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.lg)
                .frame(maxWidth: .infinity)
                .background(familyAlert == .sent ? Color.brandSuccess : Color.brandPrimaryBlue,
                            in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(familyAlert == .sending)
            .accessibilityLabel(Text(familyAlert == .sent ? "emg_alert_sent" : "emg_alert_family"))
        }
    }

    private var familyAlertSubtitle: LocalizedStringKey {
        switch familyAlert {
        case .idle:    return "emg_alert_family_subtitle"
        case .sending: return "emg_alert_sending"
        case .sent:    return "emg_alert_again"
        case .failed:  return "emg_alert_failed"
        }
    }

    private func sendFamilyAlert() {
        guard let property = propertyService.primary else { return }
        let sender = profileService.profile?.preferredName ?? "Me"
        let body = String(format: String(localized: "emg_alert_message"), property.name)
        familyAlert = .sending
        Task {
            do {
                try await messageService.send(propertyId: property.id, senderName: sender, body: body)
                familyAlert = .sent
                HapticFeedback.success()
            } catch {
                familyAlert = .failed
                HapticFeedback.error()
            }
        }
    }

    // MARK: Flashlight — instant, no checkbox
    //
    // Tap = light. While on, the whole card turns torch-yellow so the state
    // is readable from arm's length.

    private var torchCard: some View {
        Button {
            setTorch(!torchOn)
            HapticFeedback.impact(.medium)
        } label: {
            torchLabel
        }
        .buttonStyle(.plain)
        .disabled(!Self.hasTorch)
        .opacity(Self.hasTorch ? 1 : 0.4)
        .accessibilityLabel(Text(torchOn ? "emergency_torch_on" : "emergency_torch_off"))
    }

    @ViewBuilder
    private var torchLabel: some View {
        let content = HStack(spacing: AppSpacing.base) {
            Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(AppFont.scaled(28, weight: .bold))
            Text(torchOn ? "emergency_torch_on" : "emergency_torch_off")
                .font(AppFont.scaled(20, weight: .bold))
            Spacer()
        }
        .foregroundStyle(torchOn ? Color.black : Color.primary)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
        .frame(maxWidth: .infinity)

        if torchOn {
            content
                .background(Color.yellow, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        } else {
            content
                .contentShape(Rectangle())
                .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private static var hasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }

    // MARK: Dynamic Island pin
    //
    // During a real incident you leave this page constantly — calling people,
    // photographing damage. Pinning starts the emergency Live Activity: the
    // elapsed time lives in the island and one tap brings this page back.

    private var islandPinCard: some View {
        Button {
            if incidentPinned {
                LiveActivityService.shared.endEmergency()
                incidentPinned = false
                HapticFeedback.impact(.light)
            } else {
                LiveActivityService.shared.startEmergency()
                // Reflect reality: the start is a no-op when Live Activities
                // are off in iOS or in the app's settings.
                incidentPinned = LiveActivityService.shared.isActive(.emergency)
                if incidentPinned { HapticFeedback.warning() }
            }
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "light.beacon.max.fill",
                                 color: incidentPinned ? Color.brandDanger : .gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text(incidentPinned ? "emergency_pin_on" : "emergency_pin_off")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text("emergency_pin_subtitle")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: incidentPinned ? "circle.fill" : "circle")
                    .font(AppFont.caption)
                    .foregroundStyle(incidentPinned ? Color.brandDanger : Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .accessibilityLabel(Text(incidentPinned ? "emergency_pin_on" : "emergency_pin_off"))
    }

    // MARK: Mini-guides — "what do I do if…"

    private var guidesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("emg_guides_header")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(EmergencyScenario.allCases) { scenario in
                    Button {
                        activeGuide = scenario
                        HapticFeedback.impact(.medium)
                    } label: {
                        VStack(spacing: AppSpacing.sm) {
                            Image(systemName: scenario.icon)
                                .font(AppFont.scaled(28, weight: .semibold))
                                .foregroundStyle(scenario.color)
                            Text(scenario.titleKey)
                                .font(AppFont.headline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .padding(.vertical, AppSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .liquidGlass(cornerRadius: AppRadius.xl)
                    .accessibilityLabel(Text(scenario.titleKey))
                }
            }
        }
    }

    /// The flood guide links to the household's own "main water valve" place.
    /// Matched by title keywords across the app's languages — honest best
    /// effort: no match, no link.
    private var waterValvePlace: EmergencyNote? {
        let keywords = ["robinet", "valve", "haupthahn", "absperr", "wasser",
                        "vanne", "eau", "kraan", "water", "apa", "apă"]
        return notes.first { note in
            let title = note.title.lowercased()
            return keywords.contains { title.contains($0) }
        }
    }

    // MARK: Critical places (with photos)

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("emergency_places_header")
            if notes.isEmpty {
                Text("emergency_places_empty")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.xxs)
            }
            VStack(spacing: 8) {
                ForEach(notes) { note in
                    placeRow(note)
                }
            }
            Button {
                showAddNote = true
                HapticFeedback.impact(.medium)
            } label: {
                Label("emergency_add_place", systemImage: "plus")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.primary.opacity(AppOpacity.subtleFill),
                                in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// With a photo: big thumbnail, tap opens it fullscreen (finding the
    /// valve beats reading about it). Without: tap edits, as before.
    /// Long-press always offers Edit / Delete.
    private func placeRow(_ note: EmergencyNote) -> some View {
        let image = placeImages[note.id]
        return Button {
            if let image {
                photoItem = EmergencyPhotoItem(title: note.title, image: image)
                HapticFeedback.impact(.medium)
            } else {
                editingNote = note
            }
        } label: {
            HStack(spacing: AppSpacing.base) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                } else {
                    ColoredIconBadge(icon: "mappin.and.ellipse", color: .orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title)
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Text(note.detail)
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                Image(systemName: image != nil ? "arrow.up.left.and.arrow.down.right" : "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .accessibilityLabel(image != nil
                            ? Text("emg_place_photo_a11y \(note.title)")
                            : Text(note.title))
        .contextMenu {
            Button {
                editingNote = note
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                notes.removeAll { $0.id == note.id }
                saveNotes()
                EmergencyPlaceImageStore.delete(for: note.id)
                placeImages[note.id] = nil
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func applyPhotoChange(_ change: EmergencyPlacePhotoChange, id: UUID) {
        switch change {
        case .unchanged:
            return
        case .set(let image):
            placeImages[id] = image
            Task.detached(priority: .utility) {
                EmergencyPlaceImageStore.save(image, for: id)
            }
        case .removed:
            placeImages[id] = nil
            Task.detached(priority: .utility) {
                EmergencyPlaceImageStore.delete(for: id)
            }
        }
    }

    // MARK: Insurance

    @ViewBuilder
    private var insuranceSection: some View {
        let docs = documentService.documents.filter { $0.category == "insurance" }
        if !docs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("emergency_docs_header")
                VStack(spacing: 8) {
                    ForEach(docs) { doc in
                        Button {
                            router.navigate(to: .documents(id: nil))
                        } label: {
                            HStack(spacing: 12) {
                                ColoredIconBadge(icon: doc.categoryIcon, color: Color.brandSuccess)
                                Text(doc.name)
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.primary.opacity(0.28))
                            }
                            .padding(.horizontal, AppSpacing.base)
                            .padding(.vertical, AppSpacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(cornerRadius: AppRadius.lg)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ t: LocalizedStringKey) -> some View {
        Text(t)
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .padding(.leading, AppSpacing.xxs)
    }

    // MARK: Dialing

    private func call(_ number: String) {
        let clean = number.filter { $0.isNumber || $0 == "+" }
        guard !clean.isEmpty, let url = URL(string: "tel://\(clean)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Gas number (editable, per property, device-local)

    private var gasNumberKey: String {
        if let pid = propertyService.primary?.id {
            return "prvio.emergency.gasNumber.\(pid.uuidString)"
        }
        return "prvio.emergency.gasNumber"
    }

    private func loadGasNumber() {
        gasNumber = UserDefaults.standard.string(forKey: gasNumberKey) ?? Self.defaultGasNumber
    }

    private func saveGasNumber() {
        let trimmed = gasEditText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.defaultGasNumber {
            UserDefaults.standard.removeObject(forKey: gasNumberKey)
            gasNumber = Self.defaultGasNumber
        } else {
            UserDefaults.standard.set(trimmed, forKey: gasNumberKey)
            gasNumber = trimmed
        }
    }

    // MARK: Storage (device-local, works with zero connectivity)

    private func load() {
        incidentPinned = LiveActivityService.shared.isActive(.emergency)
        loadGasNumber()
        if let d = UserDefaults.standard.data(forKey: "prvio.emergency"),
           let decoded = try? JSONDecoder().decode([EmergencyContact].self, from: d) {
            contacts = decoded
        }
        if let d = UserDefaults.standard.data(forKey: "prvio.emergency.notes"),
           let decoded = try? JSONDecoder().decode([EmergencyNote].self, from: d) {
            notes = decoded
        }
        reloadPlaceImages()
    }

    /// Decode place photos off the main thread — camera JPEGs are the one
    /// thing on this page heavy enough to stutter a panicked scroll.
    private func reloadPlaceImages() {
        let ids = notes.map(\.id)
        Task {
            placeImages = await Self.loadPlaceImages(ids: ids)
        }
    }

    private nonisolated static func loadPlaceImages(ids: [UUID]) async -> [UUID: UIImage] {
        var loaded: [UUID: UIImage] = [:]
        for id in ids {
            if let img = EmergencyPlaceImageStore.load(for: id) {
                loaded[id] = img
            }
        }
        return loaded
    }

    private func saveContacts() {
        if let d = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(d, forKey: "prvio.emergency")
        }
    }

    private func saveNotes() {
        if let d = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(d, forKey: "prvio.emergency.notes")
        }
    }
}

// MARK: - Emergency contact (device-local)

struct EmergencyContact: Identifiable, Codable {
    var id = UUID()
    var name: String
    var role: String
    var phone: String
    var color: String = "red"
}

private struct AddEmergencyContactSheet: View {
    let onSave: (EmergencyContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var phone = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "emergency_contact_name_ph"), text: $name)
                    TextField(String(localized: "emergency_contact_role_ph"), text: $role)
                    TextField(String(localized: "emergency_contact_phone_ph"), text: $phone)
                        .keyboardType(.phonePad)
                } footer: {
                    Text("emergency_note_footer")
                }
            }
            .navigationTitle(Text("emergency_add_contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(EmergencyContact(name: name, role: role, phone: phone))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || phone.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
