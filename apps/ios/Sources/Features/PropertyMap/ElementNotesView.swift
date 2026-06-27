import SwiftUI
import PhotosUI
import Supabase

// Notes section embedded in the element detail. Notes can be locked; locked
// notes are encrypted and revealed only after Face ID / PIN unlock.
// Unlocked notes can also hold a checklist and photos.

struct ElementNotesSection: View {
    let element: PropertyElement

    @StateObject private var noteService = ElementNoteService()
    @ObservedObject private var lock = NoteLockManager.shared

    @State private var editorNote: ElementNote?      // existing note being edited
    @State private var showNewEditor = false
    @State private var showPINSheet = false
    @State private var pinPurpose: PINPurpose = .unlock

    private enum PINPurpose { case setup, unlock }

    private var notes: [ElementNote] { noteService.notes(for: element.id) }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Notes", systemImage: "note.text")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showNewEditor = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    }
                }

                if notes.isEmpty {
                    Text("No notes yet").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(notes) { note in
                        noteRow(note)
                        if note.id != notes.last?.id {
                            Divider().opacity(0.1)
                        }
                    }
                }
            }
        }
        .task { await noteService.load(elementId: element.id) }
        .sheet(isPresented: $showNewEditor) {
            ElementNoteEditorSheet(element: element, existing: nil)
                .environmentObject(noteService)
        }
        .sheet(item: $editorNote) { note in
            ElementNoteEditorSheet(element: element, existing: note)
                .environmentObject(noteService)
        }
        .sheet(isPresented: $showPINSheet) {
            NotePINSheet(mode: pinPurpose == .setup ? .setup : .enter) {
                showPINSheet = false
            }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: ElementNote) -> some View {
        if note.isLocked && !lock.isUnlocked {
            Button { Task { await unlock() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundStyle(.orange)
                    Text("Locked note — tap to unlock")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: lock.biometryAvailable ? "faceid" : "key.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    if note.isLocked {
                        Image(systemName: "lock.open.fill").font(.system(size: 12)).foregroundStyle(.orange).padding(.top, 2)
                    }
                    Text(noteService.displayBody(note))
                        .font(.system(size: 14)).foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Button { editorNote = note } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { Task { await noteService.delete(note) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(.leading, 4)
                    }
                }

                // Checklist
                if !note.checklist.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(note.checklist) { item in
                            Button { Task { await noteService.toggleChecklistItem(note, itemId: item.id) } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.done ? Color.green : .secondary)
                                    Text(item.text)
                                        .font(.system(size: 13))
                                        .strikethrough(item.done)
                                        .foregroundStyle(item.done ? .secondary : .primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, note.isLocked ? 22 : 0)
                }

                // Photos
                if !note.photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(note.photos, id: \.self) { u in
                                AsyncImage(url: URL(string: u)) { phase in
                                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                                    else { Color.primary.opacity(0.06) }
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func unlock() async {
        if lock.biometryAvailable {
            if await lock.unlockBiometric() { return }
        }
        // Fallback to PIN
        pinPurpose = .unlock
        showPINSheet = true
    }
}

// MARK: - Note editor

struct ElementNoteEditorSheet: View {
    let element: PropertyElement
    let existing: ElementNote?

    @EnvironmentObject private var noteService: ElementNoteService
    @ObservedObject private var lock = NoteLockManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var body_ = ""
    @State private var locked = false
    @State private var showPINSetup = false
    @State private var checklist: [ChecklistItem] = []
    @State private var newItem = ""
    @State private var photoURLs: [String] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false

    private var canSave: Bool {
        !body_.trimmingCharacters(in: .whitespaces).isEmpty || !checklist.isEmpty || !photoURLs.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        GlassCard(padding: 12) {
                            TextEditor(text: $body_)
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .font(.system(size: 15))
                        }
                        GlassCard(padding: 14) {
                            Toggle(isOn: $locked) {
                                Label("Lock (Face ID / PIN)", systemImage: "lock.fill")
                                    .font(.subheadline)
                            }
                            .tint(.orange)
                            .onChange(of: locked) { _, on in
                                if on && !lock.hasPIN { showPINSetup = true }
                                if on { checklist = []; photoURLs = [] } // rich content only for unlocked
                            }
                        }

                        if !locked {
                            checklistCard
                            photosCard
                        }
                        Spacer(minLength: 20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(existing == nil ? "New note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPINSetup) {
                NotePINSheet(mode: .setup) { showPINSetup = false }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    uploading = true
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data), let url = await uploadNotePhoto(img) {
                        photoURLs.append(url)
                    }
                    uploading = false
                    photoItem = nil
                }
            }
        }
        .onAppear {
            if let existing {
                locked = existing.isLocked
                body_ = existing.isLocked ? (NoteLockManager.shared.decrypt(existing.body) ?? "") : existing.body
                checklist = existing.checklist
                photoURLs = existing.photoUrls
            }
        }
    }

    private var checklistCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Checklist", systemImage: "checklist").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach($checklist) { $item in
                    HStack(spacing: 8) {
                        Button { item.done.toggle() } label: {
                            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? Color.green : .secondary)
                        }.buttonStyle(.plain)
                        TextField("Item", text: $item.text).font(.system(size: 14))
                        Button { checklist.removeAll { $0.id == item.id } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.3))
                        }.buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Add item", text: $newItem).font(.system(size: 14))
                        .onSubmit(addChecklistItem)
                    Button(action: addChecklistItem) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    }.buttonStyle(.plain).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var photosCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Photos", systemImage: "photo").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if uploading { ProgressView().scaleEffect(0.7) }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    }
                }
                if !photoURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photoURLs, id: \.self) { u in
                                AsyncImage(url: URL(string: u)) { phase in
                                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                                    else { Color.primary.opacity(0.06) }
                                }
                                .frame(width: 70, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contextMenu {
                                    Button(role: .destructive) { photoURLs.removeAll { $0 == u } } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addChecklistItem() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        checklist.append(ChecklistItem(text: t))
        newItem = ""
    }

    private func uploadNotePhoto(_ image: UIImage) async -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let uid = supabase.auth.currentSession?.user.id.uuidString ?? "anon"
        let path = "\(uid)/notes/\(element.id.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await supabase.storage.from("documents")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            return try supabase.storage.from("documents").getPublicURL(path: path).absoluteString
        } catch { return nil }
    }

    private func save() async {
        let text = body_.trimmingCharacters(in: .whitespaces)
        guard canSave else { return }
        let cl = locked ? [] : checklist.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let ph = locked ? [] : photoURLs
        if let existing {
            await noteService.update(existing, body: text, locked: locked, checklist: cl, photoUrls: ph)
        } else {
            await noteService.add(elementId: element.id, propertyId: element.propertyId, body: text, locked: locked, checklist: cl, photoUrls: ph)
        }
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - PIN sheet

struct NotePINSheet: View {
    enum Mode { case setup, enter }
    let mode: Mode
    let onDone: () -> Void

    @ObservedObject private var lock = NoteLockManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var confirm = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44)).foregroundStyle(.orange)
                    Text(mode == .setup ? "Set a PIN for locked notes" : "Enter your PIN")
                        .font(.headline)
                    SecureField("PIN (min 4 digits)", text: $pin)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    if mode == .setup {
                        SecureField("Confirm PIN", text: $confirm)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 220)
                    }
                    if !error.isEmpty {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    Button(mode == .setup ? "Save PIN" : "Unlock") { submit() }
                        .fontWeight(.semibold)
                        .disabled(pin.count < 4)
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func submit() {
        switch mode {
        case .setup:
            guard pin == confirm else { error = String(localized: "PINs don't match"); return }
            lock.setPIN(pin)
            HapticFeedback.success()
            onDone(); dismiss()
        case .enter:
            if lock.verifyPIN(pin) {
                HapticFeedback.success()
                onDone(); dismiss()
            } else {
                error = String(localized: "Wrong PIN")
                HapticFeedback.warning()
            }
        }
    }
}
