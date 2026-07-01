import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var profileService: ProfileService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var lastName = ""
    @State private var firstName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var socialLinks: [SocialLink] = []
    @State private var error: String?

    private let platforms = ["instagram", "facebook", "whatsapp", "telegram", "linkedin", "tiktok", "twitter", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        field("Display Name", placeholder: "What should ARIA call you?", text: $displayName)
                        field("Last Name", placeholder: "Last name", text: $lastName)
                        field("First Name", placeholder: "First name", text: $firstName)
                        birthDateField
                        field("Phone", placeholder: "+1 xxx xxx xxxx", text: $phone)
                            .keyboardType(.phonePad)
                        field("Email", placeholder: "name@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        socialSection
                        notesField

                        if let error {
                            Text(LocalizedStringKey(error))
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        saveButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { loadCurrentValues() }
    }

    // MARK: - Fields

    private func field(_ label: LocalizedStringKey, placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func fieldLabel(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var birthDateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Date of Birth")
            HStack {
                if hasBirthDate {
                    DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                    Spacer()
                    Button { withAnimation { hasBirthDate = false } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { withAnimation { hasBirthDate = true } } label: {
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(.tint)
                            Text("Add date of birth").foregroundStyle(Color.primary.opacity(0.5))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Notes")
            TextField("Notes…", text: $notes, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .lineLimit(3...8)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Social media

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("Social media")
                Spacer()
                Menu {
                    ForEach(platforms, id: \.self) { p in
                        Button {
                            socialLinks.append(SocialLink(platform: p, handle: ""))
                            HapticFeedback.selection()
                        } label: {
                            Label(SocialLink(platform: p, handle: "").platformLabel, systemImage: SocialLink(platform: p, handle: "").platformIcon)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.tint)
                }
            }

            if socialLinks.isEmpty {
                Text("Add accounts with \"+\" (Instagram, WhatsApp, etc.)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .padding(.vertical, 4)
            } else {
                ForEach($socialLinks) { $link in
                    HStack(spacing: 10) {
                        Image(systemName: link.platformIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(link.platformColor)
                            .frame(width: 26, height: 26)
                            .background(link.platformColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        TextField(link.platformLabel, text: $link.handle)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .textInputAutocapitalization(.never)
                        Button {
                            socialLinks.removeAll { $0.id == link.id }
                            HapticFeedback.selection()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if profileService.isSaving {
                    ProgressView().tint(.black)
                } else {
                    Text("Save Changes").font(AppFont.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(profileService.isSaving)
    }

    // MARK: - Load / Save

    private func loadCurrentValues() {
        guard let p = profileService.profile else { return }
        displayName = p.displayName ?? ""
        lastName = p.lastName ?? ""
        firstName = p.firstName ?? ""
        phone = p.phone ?? ""
        email = p.email
        notes = p.notes ?? ""
        socialLinks = p.socialLinks ?? []
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        if let bd = p.birthDate, let d = iso.date(from: bd) {
            birthDate = d
            hasBirthDate = true
        }
    }

    private func save() {
        error = nil
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        // Combine first/last into full name (keeps existing displays working).
        let composedFull = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let cleanedLinks = socialLinks.filter { !$0.handle.trimmingCharacters(in: .whitespaces).isEmpty }

        Task {
            do {
                try await profileService.update(
                    displayName: displayName,
                    fullName: composedFull,
                    firstName: firstName,
                    lastName: lastName,
                    birthDate: hasBirthDate ? iso.string(from: birthDate) : nil,
                    phone: phone,
                    email: email,
                    socialLinks: cleanedLinks,
                    notes: notes
                )
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
