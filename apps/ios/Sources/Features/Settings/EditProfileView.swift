import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var profileService: ProfileService
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var fullName = ""
    @State private var phone = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        field("Display Name", placeholder: "How should ARIA call you?", text: $displayName)
                        field("Full Name", placeholder: "Your full name", text: $fullName)
                        field("Phone", placeholder: "+40 7xx xxx xxx", text: $phone)
                            .keyboardType(.phonePad)

                        if let error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            save()
                        } label: {
                            Group {
                                if profileService.isSaving {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("Save Changes")
                                        .font(.system(size: 16, weight: .semibold))
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { loadCurrentValues() }
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            TextField(placeholder, text: text)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(14)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func loadCurrentValues() {
        guard let p = profileService.profile else { return }
        displayName = p.displayName ?? ""
        fullName = p.fullName
        phone = p.phone ?? ""
    }

    private func save() {
        error = nil
        Task {
            do {
                try await profileService.update(
                    fullName: fullName,
                    displayName: displayName,
                    phone: phone.isEmpty ? nil : phone
                )
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
