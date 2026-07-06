import SwiftUI
import CoreNFC
import PassKit

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

    var cardGradient: [Color] {
        switch linkedType {
        case "zone":      return [Color(red: 0.12, green: 0.32, blue: 0.86), Color(red: 0.04, green: 0.14, blue: 0.60)]
        case "appliance": return [Color(red: 0.22, green: 0.18, blue: 0.82), Color(red: 0.48, green: 0.10, blue: 0.68)]
        case "element":   return [Color(red: 0.50, green: 0.08, blue: 0.72), Color(red: 0.68, green: 0.04, blue: 0.44)]
        default:          return [Color(red: 0.18, green: 0.22, blue: 0.32), Color(red: 0.08, green: 0.10, blue: 0.18)]
        }
    }
}

// MARK: - PKAddPassButton wrapper

struct AddToWalletButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let btn = PKAddPassButton(addPassButtonStyle: .blackOutline)
        btn.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return btn
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

// MARK: - NFCWalletView

struct NFCWalletView: View {
    @State private var nfc = NFCScanService.shared

    @State private var tags: [NFCTag] = []
    @State private var showAddSheet    = false
    @State private var pendingUID: String?
    @State private var addingTagId: UUID?
    @State private var showScanError   = false
    @State private var scanErrorMsg    = ""
    @State private var showWalletError = false
    @State private var walletErrorMsg  = ""

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
                        VStack(spacing: 20) {
                            ForEach(tags) { tag in
                                cardSection(tag)
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.md)
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
                    Button { scanForNewTag() } label: {
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
        .alert("Scan Error", isPresented: $showScanError) {
            Button("OK", role: .cancel) {}
        } message: { Text(scanErrorMsg) }
        .alert("Apple Wallet", isPresented: $showWalletError) {
            Button("OK", role: .cancel) {}
        } message: { Text(walletErrorMsg) }
    }

    // MARK: - Card section (card + controls)

    private func cardSection(_ tag: NFCTag) -> some View {
        VStack(spacing: 12) {
            walletCard(tag)

            HStack(spacing: 12) {
                if WalletPassService.shared.canAddPasses {
                    if addingTagId == tag.id {
                        HStack(spacing: 8) {
                            ProgressView().tint(.primary)
                            Text("Adding…")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 44)
                    } else {
                        AddToWalletButton {
                            Task { await addTagToWallet(tag) }
                        }
                        .frame(height: 44)
                    }
                }

                Spacer()

                Button {
                    rescanTag(tag)
                } label: {
                    Image(systemName: "wave.3.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rescan tag")

                Button(role: .destructive) {
                    HapticFeedback.warning()
                    withAnimation {
                        tags.removeAll { $0.id == tag.id }
                        saveTags()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .background(Color.red.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Delete"))
            }
        }
    }

    // MARK: - Wallet card

    private func walletCard(_ tag: NFCTag) -> some View {
        ZStack {
            // Gradient background
            LinearGradient(colors: tag.cardGradient,
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)

            // Decorative NFC waves
            HStack {
                Spacer()
                Image(systemName: "wave.3.right")
                    .font(.system(size: 90, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.08))
                    .offset(x: 20, y: 0)
            }

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Top row
                HStack(alignment: .top) {
                    Text("PRVIO")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .tracking(3)
                    Spacer()
                    Image(systemName: tag.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()

                // Tag name
                Text(tag.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer().frame(height: 10)

                // Bottom row
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tag.typeLabel.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .tracking(1.5)
                        Text(tag.linkedName.isEmpty ? "Standalone" : tag.linkedName)
                            .font(AppFont.footnote)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(tag.uid.prefix(12).uppercased())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(22)
        }
        .frame(height: 175)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .shadow(color: (tag.cardGradient.first ?? .blue).opacity(0.45),
                radius: 14, y: 7)
    }

    // MARK: - Add to Apple Wallet

    private func addTagToWallet(_ tag: NFCTag) async {
        addingTagId = tag.id
        defer { addingTagId = nil }

        do {
            try await WalletPassService.shared.addNFCTagToWallet(tag: tag)
        } catch {
            walletErrorMsg = error.localizedDescription
            showWalletError = true
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
        VStack {
            Spacer()
            EmptyStateView(
                icon: "wave.3.right",
                title: "No NFC tags yet",
                message: "Scan an NFC tag to link it to a room,\nappliance, or element in your property.",
                actionLabel: "Scan First Tag",
                action: { scanForNewTag() },
                tint: .blue
            )
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
                Color.clear
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
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        // Name
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Name")
                                    .font(AppFont.captionStrong)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                TextField("e.g. Front Door, Garage, Boiler Room", text: $name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        // Linked type
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Links to")
                                    .font(AppFont.captionStrong)
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
                                        .padding(.top, AppSpacing.xxs)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        // Icon picker
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Icon")
                                    .font(AppFont.captionStrong)
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
                                                .foregroundStyle(selectedIcon == icon ? .blue : Color.primary.opacity(AppOpacity.mediumText))
                                                .frame(width: 44, height: 44)
                                                .background(
                                                    selectedIcon == icon
                                                        ? Color.blue.opacity(0.14)
                                                        : Color.primary.opacity(AppOpacity.hairline),
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        Spacer(minLength: 40)
                    }
                    .padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle("Register Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
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
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }
}
