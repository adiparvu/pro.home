import SwiftUI
import ContactsUI

// MARK: - iMessage-style attachment menu

/// Vertical translucent action panel modeled on iMessage's "+" menu: one
/// action per row — a colored 44pt icon disc on the left, a large regular
/// label on the right — floating on ultra-thin material.
struct ChatAttachmentSheet: View {
    var onPhotos: () -> Void
    var onCamera: () -> Void
    var onLocation: (() -> Void)? = nil
    var onDocument: (() -> Void)? = nil
    var onContact: () -> Void
    var onPoll: (() -> Void)? = nil
    var onEvent: (() -> Void)? = nil
    var onSendLater: (() -> Void)? = nil
    var onStickers: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private func pick(_ action: @escaping () -> Void) {
        dismiss()
        // Let the sheet finish dismissing before presenting the next one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.base) {
                row("Photos", "photo.on.rectangle.angled", .blue) { pick(onPhotos) }
                row("Camera", "camera.fill", Color(white: 0.25)) { pick(onCamera) }
                if let onLocation {
                    row("Location", "location.fill", .green) { pick(onLocation) }
                }
                row("Contact", "person.crop.circle.fill", Color(white: 0.45)) { pick(onContact) }
                if let onDocument {
                    row("Document", "doc.fill", .blue) { pick(onDocument) }
                }
                if let onPoll {
                    row("Poll", "chart.bar.fill", .orange) { pick(onPoll) }
                }
                if let onEvent {
                    row("Event", "calendar", .red) { pick(onEvent) }
                }
                if let onSendLater {
                    row("Send Later", "clock.badge", .brandSkyBlue) { pick(onSendLater) }
                }
                if let onStickers {
                    row("Stickers", "face.smiling", .yellow) { pick(onStickers) }
                }
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(520), .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(AppRadius.sheet)
        .presentationDragIndicator(.hidden)
    }

    private func row(_ label: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.lg) {
                ZStack {
                    Circle().fill(color.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 44, height: 44)
                Text(LocalizedStringKey(label))
                    .font(AppFont.menuRow)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
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
