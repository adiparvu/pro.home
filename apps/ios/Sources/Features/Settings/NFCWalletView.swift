import SwiftUI
import CoreNFC

// MARK: - NFC Tag Model

struct NFCTag: Identifiable, Codable {
    var id: UUID = UUID()
    var uid: String
    var name: String
    var linkedType: String    // "zone" | "appliance" | "element" | "none"
    var linkedName: String
    var icon: String
    var scannedAt: Date

    var typeLabel: String {
        switch linkedType {
        case "zone":      return "Zone"
        case "appliance": return "Appliance"
        case "element":   return "Element"
        default:          return "Tag"
        }
    }

    var typeColor: Color {
        switch linkedType {
        case "zone":      return .blue
        case "appliance": return Color(red: 0.2, green: 0.55, blue: 0.95)
        case "element":   return .purple
        default:          return .gray
        }
    }
}

// MARK: - NFCWalletView

struct NFCWalletView: View {
    @StateObject private var nfc = NFCScanService.shared

    @State private var tags: [NFCTag] = []
    @State private var showAddSheet    = false
    @State private var pendingUID: String?
    @State private var showScanError   = false
    @State private var scanErrorMsg    = ""

    private let storageKey = "prvio.nfcTags"

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                PageHeader(titleKey: "NFC Keys", subtitleKey: "INTEGRATIONS")

                if tags.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(tags) { tag in
                                tagCard(tag)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        Spacer(minLength: 100)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if nfc.isScanning {
                    ProgressView().tint(.accentColor)
                } else {
                    Button {
                        scanForNewTag()
                    } label: {
                        Label("Scan Tag", systemImage: "wave.3.right.circle.fill")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .onAppear { loadTags() }
        .sheet(isPresented: $showAddSheet) {
            if let uid = pendingUID {
                NFCTagNameSheet(uid: uid) { newTag in
                    tags.insert(newTag, at: 0)
                    saveTags()
                    pendingUID = nil
                }
            }
        }
        .alert("NFC Error", isPresented: $showScanError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scanErrorMsg)
        }
    }

    // MARK: - Scan

    private func scanForNewTag() {
        guard NFCScanService.isSupported else {
            scanErrorMsg = "NFC is not available on this device."
            showScanError = true
            return
        }
        HapticFeedback.impact(.medium)
        nfc.scan(prompt: "Hold iPhone near the NFC tag to register it") { uid in
            pendingUID = uid
            showAddSheet = true
        }
    }

    // MARK: - Tag card

    private func tagCard(_ tag: NFCTag) -> some View {
        GlassCard(padding: 16) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tag.typeColor.opacity(0.14))
                        .frame(width: 50, height: 50)
                    Image(systemName: tag.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tag.typeColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 5) {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 9))
                        Text(tag.typeLabel)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(tag.typeColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tag.typeColor.opacity(0.1), in: Capsule())

                    if !tag.linkedName.isEmpty {
                        Label(tag.linkedName, systemImage: "link")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(spacing: 4) {
                    Button {
                        rescanTag(tag)
                    } label: {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text(relativeDate(tag.scannedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                tags.removeAll { $0.id == tag.id }
                saveTags()
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - Rescan (update last scanned date)

    private func rescanTag(_ tag: NFCTag) {
        guard NFCScanService.isSupported else { return }
        HapticFeedback.impact(.light)
        nfc.scan(prompt: "Hold iPhone near \(tag.name) to confirm") { _ in
            if let idx = tags.firstIndex(where: { $0.id == tag.id }) {
                tags[idx].scannedAt = Date()
                saveTags()
                HapticFeedback.success()
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "wave.3.right")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.blue.opacity(0.45))
            }
            Text("No NFC tags yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text("Scan an NFC tag to link it to a room,\nappliance, or element in your property.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button { scanForNewTag() } label: {
                Label("Scan First Tag", systemImage: "wave.3.right.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 13)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!NFCScanService.isSupported)
            Spacer()
        }
    }

    // MARK: - Persistence

    private func saveTags() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadTags() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([NFCTag].self, from: data) else { return }
        tags = saved
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let df = DateFormatter(); df.dateStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Name + Link Sheet

struct NFCTagNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let uid: String
    let onSave: (NFCTag) -> Void

    @State private var name        = ""
    @State private var linkedType  = "zone"
    @State private var linkedName  = ""
    @State private var selectedIcon = "wave.3.right"

    private let typeOptions = ["zone", "appliance", "element", "none"]
    private let iconOptions = [
        "wave.3.right", "door.left.hand.open", "lock.fill",
        "washer.fill", "lightbulb.fill", "camera.fill",
        "house.fill", "car.fill", "server.rack"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // UID preview
                        GlassCard(padding: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "wave.3.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.blue)
                                    .frame(width: 26)
                                Text("Tag ID: \(uid.prefix(16))…")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Color.primary.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 20)

                        // Name
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                TextField("e.g. Front Door, Garage, Boiler Room", text: $name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Linked type
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Links to")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Picker("", selection: $linkedType) {
                                    Text("Zone / Room").tag("zone")
                                    Text("Appliance").tag("appliance")
                                    Text("Element").tag("element")
                                    Text("Standalone").tag("none")
                                }
                                .pickerStyle(.segmented)

                                if linkedType != "none" {
                                    TextField("Name of linked \(linkedType)", text: $linkedName)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.primary)
                                        .tint(.accentColor)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // Icon picker
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Icon")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                                    ForEach(iconOptions, id: \.self) { icon in
                                        Button {
                                            selectedIcon = icon
                                            HapticFeedback.selection()
                                        } label: {
                                            Image(systemName: icon)
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundStyle(selectedIcon == icon ? .blue : Color.primary.opacity(0.5))
                                                .frame(width: 44, height: 44)
                                                .background(
                                                    selectedIcon == icon
                                                        ? Color.blue.opacity(0.14)
                                                        : Color.primary.opacity(0.06),
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Register Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let tag = NFCTag(
                            uid: uid,
                            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "NFC Tag" : name,
                            linkedType: linkedType,
                            linkedName: linkedName.trimmingCharacters(in: .whitespaces),
                            icon: selectedIcon,
                            scannedAt: Date()
                        )
                        onSave(tag)
                        HapticFeedback.success()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
