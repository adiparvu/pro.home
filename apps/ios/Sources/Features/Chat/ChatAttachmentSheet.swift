import SwiftUI
import ContactsUI

// MARK: - iMessage-style attachment menu

/// The iOS 26 iMessage "+" menu, faithfully. Two independent motions, exactly
/// like Apple's: the whole conversation BLURS behind a full-screen backdrop
/// that fades in, while the menu PANEL springs up from the "+" corner.
/// Presented as a plain overlay by the chat views — this view owns both the
/// entrance and the exit (it animates itself out, then clears `isPresented`),
/// so the caller must NOT wrap it in a transition.
struct ChatAttachmentSheet: View {
    @Binding var isPresented: Bool
    var onPhotos: () -> Void
    var onCamera: () -> Void
    var onLocation: (() -> Void)? = nil
    var onDocument: (() -> Void)? = nil
    var onContact: () -> Void
    var onPoll: (() -> Void)? = nil
    var onEvent: (() -> Void)? = nil
    var onSendLater: (() -> Void)? = nil

    /// Drives both motions. Flipped true on appear (spring in) and false on
    /// dismiss (the view stays mounted through the exit because `isPresented`
    /// only clears after the animation lands).
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var entrance: Animation {
        reduceMotion ? .easeOut(duration: 0.2)
                     : .spring(response: 0.34, dampingFraction: 0.82)
    }
    private var exit: Animation {
        reduceMotion ? .easeIn(duration: 0.18) : .snappy(duration: 0.26)
    }

    /// Animate the menu closed, THEN unmount and (optionally) run the picked
    /// action so the next surface presents over a settled screen.
    private func dismiss(then action: (() -> Void)? = nil) {
        withAnimation(exit) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            isPresented = false
            action?()
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-screen frosted backdrop — the conversation blurs behind the
            // menu, exactly like iMessage (a bare dim read as flat). Fades on
            // its OWN opacity, independent of the panel's scale.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.12))
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .accessibilityLabel(Text("Cancel"))
                .accessibilityAddTraits(.isButton)

            // The menu panel: springs up FROM the "+" corner (bottom-leading
            // anchor) and fades, over the already-blurred backdrop.
            VStack(alignment: .leading, spacing: 2) {
                row("Camera", "camera.fill", [Color(white: 0.35), Color(white: 0.15)]) { dismiss(then: onCamera) }
                row("Photos", "photo.on.rectangle.angled", [.pink, .orange]) { dismiss(then: onPhotos) }
                if let onPoll {
                    row("Poll", "chart.bar.fill", [.yellow, .orange]) { dismiss(then: onPoll) }
                }
                if let onEvent {
                    row("Event", "calendar", [.red, .pink]) { dismiss(then: onEvent) }
                }
                if let onLocation {
                    row("Location", "location.fill", [.green, .teal]) { dismiss(then: onLocation) }
                }
                row("Contact", "person.crop.circle.fill", [.blue, .cyan]) { dismiss(then: onContact) }
                if let onDocument {
                    row("Document", "doc.fill", [.indigo, .blue]) { dismiss(then: onDocument) }
                }
                if let onSendLater {
                    row("Send Later", "clock.badge", [.brandSkyBlue, .blue]) { dismiss(then: onSendLater) }
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.xs)
            .frame(width: 300, alignment: .leading)
            // Native Liquid Glass (iOS 26 `.glassEffect`), matching the
            // long-press action menu — the NON-clear variant, so it reads like
            // Apple's own menu without the wallpaper smear the interactive clear
            // glass produced (IMG_8305). Pre-26 falls back to system material.
            .liquidGlass(cornerRadius: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 22, y: 8)
            .scaleEffect(shown ? 1 : 0.55, anchor: .bottomLeading)
            .opacity(shown ? 1 : 0)
            .padding(.leading, AppSpacing.base)
            .padding(.bottom, AppSpacing.md)
        }
        .onAppear { withAnimation(entrance) { shown = true } }
    }

    private func row(_ label: LocalizedStringKey, _ icon: String, _ colors: [Color],
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.base) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: icon)
                        .font(AppFont.headline)
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                Text(label)
                    .font(AppFont.scaled(17))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contact picker (UIKit bridge)

struct ChatContactPicker: UIViewControllerRepresentable {
    let onPick: (String) -> Void   // formatted "name | phone"
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ChatContactPicker
        init(_ parent: ChatContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            let formatted = phone.isEmpty ? name : "\(name) | \(phone)"
            parent.onPick(formatted)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}
