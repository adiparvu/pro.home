import SwiftUI

// MARK: - Custom integrations manager ("connect anything")
//
// The user-facing face of custom_integrations: create a named integration for
// every external service (Home Assistant, a Zapier zap, an alarm panel, a
// Raspberry Pi script…), each with its own secret key that can be toggled,
// rotated or revoked without touching the others. Messages arrive in the
// house chat through the same cross-app-inbox gateway as the shared channel.

struct CustomIntegrationsView: View {
    @Environment(PropertyService.self) private var propertyService

    @State private var service = CustomIntegrationService()
    @State private var showAdd = false
    @State private var selectedId: UUID?

    private var propertyId: UUID? { propertyService.primary?.id }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                PageHeader(titleKey: "Custom integrations")

                heroCard

                if service.integrations.isEmpty && !service.isLoading {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(service.integrations) { integration in
                            IntegrationCardRow(integration: integration) {
                                selectedId = integration.id
                            } onToggle: { on in
                                Task { await service.setEnabled(integration, on) }
                            }
                        }
                    }
                }

                addButton

                if let err = service.error {
                    Text(err).font(AppFont.scaled(12)).foregroundStyle(.red)
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let pid = propertyId { await service.load(propertyId: pid) }
        }
        .sheet(isPresented: $showAdd) {
            IntegrationEditorSheet { name, icon, color in
                guard let pid = propertyId else { return }
                await service.create(propertyId: pid, name: name, icon: icon, color: color)
            }
            .presentationDetents([.large])
        }
        .sheet(item: Binding(
            get: { service.integrations.first { $0.id == selectedId } },
            set: { if $0 == nil { selectedId = nil } }
        )) { integration in
            IntegrationDetailSheet(integration: integration, service: service)
                .presentationDetents([.large])
        }
    }

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            ColoredIconBadge(icon: "sparkles", color: Color.brandPurple, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect anything")
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Text("Every service you connect gets its own name and secret key. Anything that can send a web request — automations, servers, sensors, bots — posts straight into your house chat.")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "puzzlepiece.extension.fill",
            title: "No integrations yet",
            message: "Each integration gets its own key that you can pause, rotate or revoke at any time."
        )
    }

    private var addButton: some View {
        Button {
            HapticFeedback.impact(.medium)
            showAdd = true
        } label: {
            Label("Add integration", systemImage: "plus")
                .font(AppFont.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.brandPurple],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct IntegrationCardRow: View {
    let integration: CustomIntegration
    let onOpen: () -> Void
    let onToggle: (Bool) -> Void

    private var tint: Color { Color(hex: integration.color) ?? .blue }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: integration.icon, color: tint, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(integration.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        lastUsedLabel
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(get: { integration.enabled }, set: onToggle))
                .labelsHidden()
                .tint(tint)
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .opacity(integration.enabled ? 1 : 0.55)
        .animation(.smooth(duration: 0.25), value: integration.enabled)
    }

    @ViewBuilder
    private var lastUsedLabel: some View {
        if let date = integration.lastUsedAt {
            HStack(spacing: 4) {
                Circle().fill(Color.brandSuccess).frame(width: 6, height: 6)
                Text("Last used \(date, format: .relative(presentation: .named))")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
        } else {
            Text("Never used yet")
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        }
    }
}

// MARK: - Identity editor (shared by create + detail)

private let kIntegrationIcons: [String] = [
    "puzzlepiece.extension.fill", "bolt.fill", "house.fill", "server.rack",
    "cpu.fill", "sensor.tag.radiowaves.forward.fill", "camera.fill", "bell.fill",
    "cloud.fill", "envelope.fill", "cart.fill", "car.fill",
    "drop.fill", "flame.fill", "leaf.fill", "lock.fill",
]

private let kIntegrationColors: [String] = [
    "#5B8AF5", "#8B5CF6", "#F59E0B", "#EF4444",
    "#10B981", "#14B8A6", "#EC4899", "#64748B",
]

private struct IntegrationIdentityEditor: View {
    @Binding var name: String
    @Binding var icon: String
    @Binding var color: String

    private var tint: Color { Color(hex: color) ?? .blue }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 76, height: 76)
                Image(systemName: icon)
                    .font(AppFont.scaled(32, weight: .medium))
                    .foregroundStyle(tint)
            }
            .animation(.smooth(duration: 0.25), value: icon)
            .animation(.smooth(duration: 0.25), value: color)

            TextField("Integration name", text: $name, prompt: Text("e.g. Home Assistant"))
                .font(AppFont.scaled(17, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.vertical, AppSpacing.md)
                .padding(.horizontal, AppSpacing.lg)
                .liquidGlass(cornerRadius: AppRadius.lg)

            VStack(alignment: .leading, spacing: 8) {
                Text("ICON")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                    ForEach(kIntegrationIcons, id: \.self) { symbol in
                        Button {
                            icon = symbol
                            HapticFeedback.selection()
                        } label: {
                            Image(systemName: symbol)
                                .font(AppFont.body)
                                .foregroundStyle(icon == symbol ? tint : Color.primary.opacity(AppOpacity.mediumText))
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle().fill(icon == symbol ? tint.opacity(0.18) : Color.primary.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("COLOR")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                HStack(spacing: 12) {
                    ForEach(kIntegrationColors, id: \.self) { hex in
                        Button {
                            color = hex
                            HapticFeedback.selection()
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .blue)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if color == hex {
                                        Image(systemName: "checkmark")
                                            .font(AppFont.scaled(11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Create sheet

private struct IntegrationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onCreate: (String, String, String) async -> Void

    @State private var name = ""
    @State private var icon = "puzzlepiece.extension.fill"
    @State private var color = "#5B8AF5"
    @State private var isSaving = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    IntegrationIdentityEditor(name: $name, icon: $icon, color: $color)

                    Text("After you create it, open the integration to copy its secret key into the external service.")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .navigationTitle(Text("Add integration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isSaving = true
                        Task {
                            await onCreate(
                                name.trimmingCharacters(in: .whitespacesAndNewlines),
                                icon, color
                            )
                            HapticFeedback.success()
                            dismiss()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Create").fontWeight(.semibold) }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Detail sheet

private struct IntegrationDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let integration: CustomIntegration
    let service: CustomIntegrationService

    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var copied: String?
    @State private var testState: TestState = .idle
    @State private var confirmDelete = false

    private enum TestState { case idle, running, ok, failed }

    init(integration: CustomIntegration, service: CustomIntegrationService) {
        self.integration = integration
        self.service = service
        _name = State(initialValue: integration.name)
        _icon = State(initialValue: integration.icon)
        _color = State(initialValue: integration.color)
    }

    private var identityChanged: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != integration.name
            || icon != integration.icon
            || color != integration.color
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    IntegrationIdentityEditor(name: $name, icon: $icon, color: $color)

                    connectionSection
                    testButton
                    dangerSection

                    if let err = service.error {
                        Text(err).font(AppFont.scaled(12)).foregroundStyle(.red)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .navigationTitle(Text(integration.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if identityChanged {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            Task {
                                await service.rename(integration, name: trimmed, icon: icon, color: color)
                                HapticFeedback.success()
                            }
                        } label: {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                }
            }
            .confirmationDialog(
                Text("Delete \"\(integration.name)\"?"),
                isPresented: $confirmDelete, titleVisibility: .visible
            ) {
                Button("Delete integration", role: .destructive) {
                    Task {
                        await service.delete(integration)
                        HapticFeedback.warning()
                        dismiss()
                    }
                }
            } message: {
                Text("This immediately cuts off the service using this key.")
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONNECTION")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            copyRow(icon: "link", tint: .blue, title: "Endpoint",
                    value: CrossAppService.endpoint.absoluteString, key: "url")
            copyRow(icon: "key.fill", tint: .orange, title: "Secret token",
                    value: integration.token.uuidString.lowercased(), key: "token", masked: true)

            Button {
                HapticFeedback.impact(.medium)
                Task { await service.rotateToken(integration) }
            } label: {
                Label("Rotate token", systemImage: "arrow.triangle.2.circlepath")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .padding(.leading, AppSpacing.xxs)

            let sample = "{\n  \"token\": \"\(integration.token.uuidString.lowercased())\",\n  \"text\": \"Salut din \(integration.name)!\"\n}"
            Text(sample)
                .font(AppFont.scaled(12, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.base)
                .liquidGlass(cornerRadius: AppRadius.lg)
                .onTapGesture {
                    UIPasteboard.general.string = sample
                    copied = "sample"
                    HapticFeedback.selection()
                }
            if copied == "sample" {
                Label("Copied", systemImage: "checkmark")
                    .font(AppFont.scaled(11)).foregroundStyle(Color.brandSuccess)
                    .padding(.leading, AppSpacing.xxs)
            }
        }
    }

    private var testButton: some View {
        Button {
            testState = .running
            Task {
                let ok = await service.sendTest(integration)
                testState = ok ? .ok : .failed
                if ok { HapticFeedback.success() } else { HapticFeedback.warning() }
            }
        } label: {
            HStack(spacing: 8) {
                switch testState {
                case .running: ProgressView().tint(.white)
                case .ok:      Image(systemName: "checkmark.circle.fill")
                case .failed:  Image(systemName: "xmark.circle.fill")
                case .idle:    Image(systemName: "paperplane.fill")
                }
                Text(testState == .ok ? "Sent — check the chat!" : "Send test message")
                    .font(AppFont.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [Color.accentColor, Color.brandPurple],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(testState == .running)
    }

    private var dangerSection: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete integration", systemImage: "trash")
                .font(AppFont.subheadline)
                .foregroundStyle(Color.brandDanger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlass(cornerRadius: AppRadius.lg)
        }
        .buttonStyle(.plain)
    }

    private func copyRow(icon: String, tint: Color, title: LocalizedStringKey,
                         value: String, key: String, masked: Bool = false) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.captionEmphasis).foregroundStyle(.primary)
                Text(masked ? String(value.prefix(8)) + "••••••••" : value)
                    .font(AppFont.scaled(12, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
                copied = key
                HapticFeedback.selection()
            } label: {
                Image(systemName: copied == key ? "checkmark" : "doc.on.doc")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(copied == key ? Color.brandSuccess : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied == key ? Text("Copied") : Text("Copy"))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }
}
