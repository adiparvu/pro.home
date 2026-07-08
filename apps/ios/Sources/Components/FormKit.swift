import SwiftUI

// MARK: - The app's one form language
//
// Every add/edit sheet is built from the same four pieces, promoted here
// from the best-looking forms already in the app (documents, tenant,
// journal): a scaffold that owns the chrome (title, Cancel, Save with
// progress, background, error alert), glass field groups, icon-led rows
// and inset dividers. Forms differ in their fields — never in their bones.

// MARK: Scaffold

struct FormScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var saveLabel: LocalizedStringKey = "Save"
    var canSave: Bool = true
    var isSaving: Bool = false
    @Binding var error: String?
    var onSave: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    content()
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(saveLabel) {
                            HapticFeedback.impact(.light)
                            onSave()
                        }
                        .font(AppFont.subheadline)
                        .foregroundStyle(canSave ? Color.accentColor : Color.primary.opacity(AppOpacity.disabled))
                        .disabled(!canSave)
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        // Every form is sheet-presented: a translucent backdrop instead of the
        // opaque app background makes the whole family read as Liquid Glass.
        // The field groups themselves are already GlassCards.
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
    }
}

// MARK: Field group (the glass card every form is made of)

struct FormGroup<Content: View>: View {
    var title: LocalizedStringKey? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .textCase(.uppercase)
                    .padding(.leading, AppSpacing.xxs)
            }
            VStack(spacing: 0) { content() }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }
}

// MARK: Rows

/// An icon-led row hosting any control (TextField, Picker, Toggle…).
struct FormRow<Content: View>: View {
    let icon: String
    var tint: Color = .blue
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(tint)
                .frame(width: 22)
            content()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.base)
    }
}

/// The inset hairline between rows of a FormGroup.
struct FormDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 54)
    }
}
