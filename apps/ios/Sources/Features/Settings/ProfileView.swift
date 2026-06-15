import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var notificationScheduler: NotificationScheduler
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var documentService: DocumentService

    @State private var showEdit = false
    @State private var showChangeEmail = false
    @State private var showChangePassword = false
    @State private var showDeleteConfirm = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showAvatarOptions = false
    @State private var showCamera = false
    @State private var toast: String?
    @State private var toastIsError = false
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"

    private var ringColor: Color { avatarRingColor(for: avatarRingColorName) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                avatarSection
                infoCard
                accountSection
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            EditProfileView().environmentObject(profileService)
        }
        .sheet(isPresented: $showChangeEmail) {
            ChangeEmailSheet { newEmail in
                Task { await changeEmail(newEmail) }
            }
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet { newPassword in
                Task { await changePassword(newPassword) }
            }
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                Task { try? await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your data will be permanently deleted. This cannot be undone.")
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhotoPick(newItem) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .sheet(isPresented: $showCamera) {
            CameraCapture { img in
                Task {
                    do {
                        try await profileService.uploadAvatar(img)
                        showToast("Avatar updated")
                    } catch {
                        showToast(error.localizedDescription, isError: true)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Change avatar", isPresented: $showAvatarOptions, titleVisibility: .visible) {
            Button("Take a photo") { showCamera = true }
            Button("Choose from Gallery") { showPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let msg = toast {
                toastView(msg, isError: toastIsError)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 100)
            }
        }
        .task {
            if profileService.profile == nil, let uid = auth.session?.user.id {
                await profileService.load(userId: uid)
            }
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                avatarImage
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .shadow(color: ringColor.opacity(0.45), radius: 16, y: 6)
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: 2.5))

                Button { showAvatarOptions = true } label: {
                    ZStack {
                        Circle().fill(.black.opacity(0.55)).frame(width: 30, height: 30)
                        if profileService.isUploadingAvatar {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(profileService.isUploadingAvatar)
                .offset(x: 4, y: 4)
            }

            Text(preferredName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            Text(auth.session?.user.email ?? "")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.5))

            ringColorPicker
        }
    }

    private var ringColorPicker: some View {
        HStack(spacing: 8) {
            ForEach(["blue", "purple", "green", "orange", "pink", "gold", "red", "teal"], id: \.self) { name in
                let c = avatarRingColor(for: name)
                Button { withAnimation(.spring(response: 0.3)) { avatarRingColorName = name } } label: {
                    ZStack {
                        Circle().fill(c).frame(width: 22, height: 22)
                        if avatarRingColorName == name {
                            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 22, height: 22)
                            Circle().strokeBorder(c, lineWidth: 1).frame(width: 26, height: 26)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // Custom ring color picker
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                        center: .center
                    ))
                    .frame(width: 22, height: 22)
                if avatarRingColorName.hasPrefix("#") {
                    Circle().strokeBorder(.white, lineWidth: 2).frame(width: 22, height: 22)
                    Circle().strokeBorder(ringColor, lineWidth: 1).frame(width: 26, height: 26)
                }
                ColorPicker("", selection: Binding(
                    get: { Color(hex: avatarRingColorName) ?? .blue },
                    set: { newColor in
                        withAnimation(.spring(response: 0.3)) {
                            avatarRingColorName = newColor.hexString()
                        }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .opacity(0.02)
                .frame(width: 44, height: 44)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let urlStr = profileService.profile?.avatarUrl,
           let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    gradientInitial
                default:
                    gradientInitial.overlay(ProgressView().tint(.white))
                }
            }
        } else {
            gradientInitial
        }
    }

    private var gradientInitial: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(preferredInitial)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                infoRow("Email", auth.session?.user.email ?? "—")
                div
                infoRow("Display Name", profileService.profile?.preferredName ?? "—")
                div
                if let fullName = profileService.profile?.fullName, !fullName.isEmpty {
                    infoRow("Full Name", fullName)
                    div
                }
                if let phone = profileService.profile?.phone, !phone.isEmpty {
                    infoRow("Phone", phone)
                    div
                }
                infoRow("Account ID", shortId)
                div
                infoRow("Member since", memberSince)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 16)
    }

    // MARK: - Account actions

    private var accountSection: some View {
        SettingsGroup(title: "Account") {
            NavSettingsRow(icon: "pencil.circle.fill", color: .blue, label: "Edit profile") {
                EditProfileView().environmentObject(profileService)
            }
            TapSettingsRow(icon: "envelope.fill", color: .orange, label: "Change email") {
                showChangeEmail = true
            }
            TapSettingsRow(icon: "key.fill", color: Color(red: 0.3, green: 0.85, blue: 0.5), label: "Change password") {
                showChangePassword = true
            }
            NavSettingsRow(icon: "shield.fill", color: .purple, label: "Safety and security") {
                SecurityView().environmentObject(auth)
            }
            NavSettingsRow(icon: "person.badge.shield.checkmark.fill", color: Color(red: 0.25, green: 0.55, blue: 1.0), label: "Trusted contact") {
                TrustedContactView().environmentObject(auth)
            }
            NavSettingsRow(icon: "bell.fill", color: .red, label: "Notifications") {
                NotificationsSettingsView()
                    .environmentObject(notificationScheduler)
                    .environmentObject(taskService)
                    .environmentObject(documentService)
            }
        }
    }

    // MARK: - Actions

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        do {
            try await profileService.uploadAvatar(image)
            showToast("Avatar updated")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func changeEmail(_ newEmail: String) async {
        do {
            try await profileService.updateEmail(newEmail)
            showToast("Check your inbox — a verification email was sent to \(newEmail)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func changePassword(_ newPassword: String) async {
        do {
            try await profileService.updatePassword(newPassword)
            showToast("Password updated successfully")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    private func showToast(_ message: String, isError: Bool = false) {
        toastIsError = isError
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation { toast = nil }
        }
    }

    private func toastView(_ message: String, isError: Bool) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(isError ? .red.opacity(0.85) : Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.95),
                        in: Capsule())
            .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private var preferredName: String {
        profileService.profile?.preferredName ?? fallbackName
    }
    private var preferredInitial: String {
        profileService.profile?.initial ?? String(fallbackName.prefix(1)).uppercased()
    }
    private var fallbackName: String {
        auth.session?.user.email?.components(separatedBy: "@").first?.capitalized ?? "User"
    }
    private var shortId: String {
        auth.session?.user.id.uuidString.components(separatedBy: "-").first ?? "—"
    }
    private var memberSince: String {
        guard let user = auth.session?.user else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: user.createdAt)
    }
}

// MARK: - Change Email Sheet

private struct ChangeEmailSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var confirm = ""

    var isValid: Bool { !email.isEmpty && email == confirm && email.contains("@") }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        emailField("envelope.fill", "New email address", $email, keyboard: .emailAddress)
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 52)
                        emailField("checkmark.circle.fill", "Confirm new email", $confirm, keyboard: .emailAddress)
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))

                    Text("A verification link will be sent to your new address. Your email will only change after you confirm it.")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.38))
                        .multilineTextAlignment(.center).padding(.horizontal, 8)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 20)
            }
            .navigationTitle("Change Email").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSave(email); HapticFeedback.success(); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func emailField(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(ph, text: b)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(keyboard).autocorrectionDisabled().textInputAutocapitalization(.never)
        }.padding(.horizontal, 16).padding(.vertical, 14)
    }
}

// MARK: - Change Password Sheet

private struct ChangePasswordSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var showPassword = false

    var isValid: Bool { password.count >= 6 && password == confirm }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        passField("lock.fill", "New password", $password)
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5).padding(.leading, 52)
                        passField("lock.rotation", "Confirm password", $confirm)
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))

                    if !password.isEmpty && password.count < 6 {
                        Text("Password must be at least 6 characters")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    if !confirm.isEmpty && password != confirm {
                        Text("Passwords don't match")
                            .font(.system(size: 12)).foregroundStyle(.red)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 20)
            }
            .navigationTitle("Change Password").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        onSave(password); HapticFeedback.success(); dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.accentColor)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func passField(_ icon: String, _ ph: String, _ b: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            SecureField(ph, text: b)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
        }.padding(.horizontal, 16).padding(.vertical, 14)
    }
}
