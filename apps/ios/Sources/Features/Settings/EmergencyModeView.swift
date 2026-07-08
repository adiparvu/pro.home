import SwiftUI
import AVFoundation

// MARK: - Emergency Mode
//
// The page for the burst pipe at 2 AM: one screen with the numbers to call,
// where the shut-off valves are, the insurance papers, and a flashlight —
// zero navigation between you and the thing you need. Critical places are
// written by the household ahead of time (a picker over property elements
// would guess; the owner knows), and everything here works offline because
// contacts and notes live on the device.

struct EmergencyModeView: View {
    @Environment(DocumentService.self) private var documentService
    @Environment(AppRouter.self) private var router

    @State private var contacts: [EmergencyContact] = []
    @State private var notes: [EmergencyNote] = []
    @State private var editingNote: EmergencyNote? = nil
    @State private var showAddNote = false
    @State private var showAddContact = false
    @State private var torchOn = false
    @State private var incidentPinned = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                PageHeader(titleKey: "emergency_title", subtitleKey: "emergency_subtitle")
                callSection
                torchCard
                islandPinCard
                placesSection
                insuranceSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear { setTorch(false) }
        .sheet(isPresented: $showAddContact) {
            AddEmergencyContactSheet { contact in
                contacts.append(contact)
                saveContacts()
            }
        }
        .sheet(isPresented: $showAddNote) {
            EmergencyNoteSheet { note in
                notes.append(note)
                saveNotes()
            }
        }
        .sheet(item: $editingNote) { note in
            EmergencyNoteSheet(editing: note) { updated in
                if let i = notes.firstIndex(where: { $0.id == updated.id }) {
                    notes[i] = updated
                    saveNotes()
                }
            }
        }
    }

    // MARK: Call

    private var callSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("emergency_call_header")
            VStack(spacing: 8) {
                ForEach(allContacts) { c in
                    Button {
                        HapticFeedback.impact(.heavy)
                        call(c.phone)
                    } label: {
                        HStack(spacing: 12) {
                            ColoredIconBadge(icon: "phone.fill", color: contactColor(c))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name)
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(.primary)
                                Text(LocalizedStringKey(c.role))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(c.phone)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(contactColor(c))
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .liquidGlass(cornerRadius: AppRadius.lg)
                    .accessibilityLabel(Text("emergency_call_a11y \(c.name)"))
                    .contextMenu {
                        if isCustom(c) {
                            Button(role: .destructive) {
                                contacts.removeAll { $0.id == c.id }
                                saveContacts()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
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

    /// 112 always leads, the standing services follow, then the
    /// household's own numbers (long-press to remove those).
    private var allContacts: [EmergencyContact] {
        [EmergencyContact(name: "112", role: String(localized: "emergency_112_role"),
                          phone: "112", color: "red"),
         EmergencyContact(name: String(localized: "emergency_gas_name"),
                          role: String(localized: "emergency_gas_role"),
                          phone: "0800-001122", color: "orange")] + contacts
    }

    private func isCustom(_ c: EmergencyContact) -> Bool {
        contacts.contains { $0.id == c.id }
    }

    private func contactColor(_ c: EmergencyContact) -> Color {
        switch c.color {
        case "blue":   return .blue
        case "orange": return .orange
        case "green":  return Color.brandSuccess
        default:       return .red
        }
    }

    private func call(_ number: String) {
        let clean = number.filter { $0.isNumber || $0 == "+" }
        guard !clean.isEmpty, let url = URL(string: "tel://\(clean)") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Flashlight

    private var torchCard: some View {
        Button {
            setTorch(!torchOn)
            HapticFeedback.impact(.medium)
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                 color: torchOn ? .yellow : .gray)
                Text(torchOn ? "emergency_torch_on" : "emergency_torch_off")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: torchOn ? "circle.fill" : "circle")
                    .font(AppFont.caption)
                    .foregroundStyle(torchOn ? .yellow : Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .disabled(!Self.hasTorch)
        .opacity(Self.hasTorch ? 1 : 0.4)
    }

    private static var hasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
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

    // MARK: Critical places

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
                    Button {
                        editingNote = note
                    } label: {
                        HStack(spacing: 12) {
                            ColoredIconBadge(icon: "mappin.and.ellipse", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title)
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(.primary)
                                Text(note.detail)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
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
                    .contextMenu {
                        Button(role: .destructive) {
                            notes.removeAll { $0.id == note.id }
                            saveNotes()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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
                            router.navigate(to: .documents)
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

    // MARK: Storage (device-local, works with zero connectivity)

    private func load() {
        incidentPinned = LiveActivityService.shared.isActive(.emergency)
        if let d = UserDefaults.standard.data(forKey: "prvio.emergency"),
           let decoded = try? JSONDecoder().decode([EmergencyContact].self, from: d) {
            contacts = decoded
        }
        if let d = UserDefaults.standard.data(forKey: "prvio.emergency.notes"),
           let decoded = try? JSONDecoder().decode([EmergencyNote].self, from: d) {
            notes = decoded
        }
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

// MARK: - Critical place note

struct EmergencyNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var detail: String
}

private struct EmergencyNoteSheet: View {
    var editing: EmergencyNote? = nil
    let onSave: (EmergencyNote) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "emergency_note_title_ph"), text: $title)
                    TextField(String(localized: "emergency_note_detail_ph"), text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("emergency_note_footer")
                }
            }
            .navigationTitle(Text(editing == nil ? "emergency_add_place" : "emergency_edit_place"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var note = editing ?? EmergencyNote(title: "", detail: "")
                        note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        note.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(note)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let editing {
                    title = editing.title
                    detail = editing.detail
                }
            }
        }
        .presentationDetents([.medium])
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
