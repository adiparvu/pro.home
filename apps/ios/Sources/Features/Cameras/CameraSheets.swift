import SwiftUI

// MARK: - Add / edit camera sheet
//
// Same form grammar as PantryItemSheet: uppercase field labels, subtle-fill
// inputs, GlassWideButton save. The password goes straight to the Keychain
// through CameraService — it never touches the persisted model. "Test
// connection" performs one real snapshot fetch and shows the frame (or the
// exact failure) inline before the user commits.

struct CameraFormSheet: View {
    @Environment(\.dismiss) private var dismiss

    let camera: SecurityCamera?

    private let service = CameraService.shared

    @State private var name = ""
    @State private var snapshotURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var notes = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case testing
        case success(UIImage)
        case failure(String)
    }

    private var trimmedURL: String {
        snapshotURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var urlIsPlausible: Bool {
        trimmedURL.lowercased().hasPrefix("http://") || trimmedURL.lowercased().hasPrefix("https://")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && urlIsPlausible
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    field(label: "cameras_field_name") {
                        TextField(String(localized: "cameras_name_placeholder"), text: $name)
                            .font(AppFont.scaled(16))
                            .padding(AppSpacing.base)
                            .background(Color.subtleFill,
                                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }

                    field(label: "cameras_field_url") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(String(localized: "cameras_url_placeholder"), text: $snapshotURL)
                                .font(AppFont.scaled(15))
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(AppSpacing.base)
                                .background(Color.subtleFill,
                                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            Text("cameras_url_hint")
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    field(label: "cameras_field_username") {
                        TextField(String(localized: "cameras_username_placeholder"), text: $username)
                            .font(AppFont.scaled(16))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(AppSpacing.base)
                            .background(Color.subtleFill,
                                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }

                    field(label: "cameras_field_password") {
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField(String(localized: "cameras_field_password"), text: $password)
                                .font(AppFont.scaled(16))
                                .textInputAutocapitalization(.never)
                                .padding(AppSpacing.base)
                                .background(Color.subtleFill,
                                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            Text("cameras_password_hint")
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    field(label: "cameras_field_notes") {
                        TextField(String(localized: "cameras_notes_placeholder"),
                                  text: $notes, axis: .vertical)
                            .font(AppFont.scaled(16))
                            .lineLimit(2...4)
                            .padding(AppSpacing.base)
                            .background(Color.subtleFill,
                                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }

                    testSection

                    GlassWideButton(icon: "checkmark",
                                    label: camera == nil ? "cameras_save_add" : "cameras_save_edit") {
                        save()
                    }
                    .disabled(!canSave)

                    if let camera {
                        Button(role: .destructive) {
                            service.delete(camera)
                            HapticFeedback.success()
                            dismiss()
                        } label: {
                            Text("cameras_delete")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .navigationTitle(camera == nil ? Text("cameras_add") : Text("cameras_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.thinMaterial)
        .onAppear {
            guard let camera else { return }
            name = camera.name
            snapshotURL = camera.snapshotURL
            username = camera.username ?? ""
            notes = camera.notes ?? ""
            password = service.password(forCameraId: camera.id)
        }
    }

    // MARK: - Test connection

    @ViewBuilder
    private var testSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            GlassWideButton(icon: "dot.radiowaves.left.and.right",
                            label: "cameras_test",
                            isBusy: testState == .testing) {
                runTest()
            }
            .disabled(!urlIsPlausible)

            switch testState {
            case .idle, .testing:
                EmptyView()
            case .success(let frame):
                VStack(alignment: .leading, spacing: 6) {
                    Color.clear
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .overlay(Image(uiImage: frame).resizable().scaledToFill())
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    Label { Text("cameras_test_ok") } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(Color.brandSuccess)
                }
                .transition(.opacity)
            case .failure(let message):
                Label { Text(verbatim: message) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(AppFont.caption)
                .foregroundStyle(Color.brandDanger)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
    }

    private func runTest() {
        testState = .testing
        let url = trimmedURL
        let user = username.trimmingCharacters(in: .whitespaces)
        let pass = password
        Task {
            let result = await CameraService.fetch(urlString: url, username: user, password: pass)
            withAnimation(.smooth(duration: 0.25)) {
                switch result {
                case .success(let image):
                    HapticFeedback.success()
                    testState = .success(image)
                case .failure(let error):
                    HapticFeedback.error()
                    testState = .failure(error.localizedMessage)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUser = username.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave else { return }

        if var existing = camera {
            existing.name = trimmedName
            existing.snapshotURL = trimmedURL
            existing.username = trimmedUser.isEmpty ? nil : trimmedUser
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            service.update(existing, password: password)
        } else {
            let new = SecurityCamera(name: trimmedName,
                                     snapshotURL: trimmedURL,
                                     username: trimmedUser.isEmpty ? nil : trimmedUser,
                                     notes: trimmedNotes.isEmpty ? nil : trimmedNotes)
            service.add(new, password: password)
        }
        HapticFeedback.success()
        dismiss()
    }

    private func field(label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
