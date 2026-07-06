import SwiftUI
import ContactsUI

// MARK: - iMessage-style attachment menu

/// The iOS 26 iMessage "+" menu, faithfully: a floating CLEAR Liquid Glass
/// panel anchored above the compose bar (not a detented sheet), colourful
/// app-style icon discs, plain 17pt labels, and a tap anywhere outside to
/// dismiss. Presented as an overlay by the chat views.
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
    var onStickers: (() -> Void)? = nil

    private func pick(_ action: @escaping () -> Void) {
        withAnimation(.snappy(duration: 0.22)) { isPresented = false }
        // Let the panel finish closing before presenting the next surface.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Tap-outside catcher with the system-style dim.
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.22)) { isPresented = false }
                }
                .accessibilityLabel(Text("Cancel"))

            VStack(alignment: .leading, spacing: 4) {
                row("Camera", "camera.fill", [Color(white: 0.35), Color(white: 0.15)]) { pick(onCamera) }
                row("Photos", "photo.on.rectangle.angled", [.pink, .orange]) { pick(onPhotos) }
                if let onStickers {
                    row("Stickers", "face.smiling", [.purple, .indigo]) { pick(onStickers) }
                }
                if let onPoll {
                    row("Poll", "chart.bar.fill", [.yellow, .orange]) { pick(onPoll) }
                }
                if let onEvent {
                    row("Event", "calendar", [.red, .pink]) { pick(onEvent) }
                }
                if let onLocation {
                    row("Location", "location.fill", [.green, .teal]) { pick(onLocation) }
                }
                row("Contact", "person.crop.circle.fill", [.blue, .cyan]) { pick(onContact) }
                if let onDocument {
                    row("Document", "doc.fill", [.indigo, .blue]) { pick(onDocument) }
                }
                if let onSendLater {
                    row("Send Later", "clock.badge", [.brandSkyBlue, .blue]) { pick(onSendLater) }
                }
            }
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.xs)
            .frame(width: 300, alignment: .leading)
            .mediaGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.leading, AppSpacing.base)
            .padding(.bottom, 8)
        }
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                Text(label)
                    .font(.system(size: 17))
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
