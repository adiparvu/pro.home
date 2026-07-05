import SwiftUI
import ContactsUI

// MARK: - WhatsApp-style attachment grid

struct ChatAttachmentSheet: View {
    var onPhotos: () -> Void
    var onCamera: () -> Void
    var onLocation: (() -> Void)? = nil
    var onDocument: (() -> Void)? = nil
    var onContact: () -> Void
    var onPoll: (() -> Void)? = nil
    var onEvent: (() -> Void)? = nil
    var onStickers: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible()), GridItem(.flexible()),
                           GridItem(.flexible()), GridItem(.flexible())]

    private func pick(_ action: @escaping () -> Void) {
        dismiss()
        // Let the sheet finish dismissing before presenting the next one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                LazyVGrid(columns: columns, spacing: 22) {
                    option("Photos", "photo.on.rectangle.angled", .blue) { pick(onPhotos) }
                    option("Camera", "camera.fill", Color(white: 0.25)) { pick(onCamera) }
                    if let onLocation {
                        option("Location", "location.fill", .green) { pick(onLocation) }
                    }
                    option("Contact", "person.crop.circle.fill", Color(white: 0.45)) { pick(onContact) }
                    if let onDocument {
                        option("Document", "doc.fill", .blue) { pick(onDocument) }
                    }
                    if let onPoll {
                        option("Poll", "chart.bar.fill", .orange) { pick(onPoll) }
                    }
                    if let onEvent {
                        option("Event", "calendar", .red) { pick(onEvent) }
                    }
                    if let onStickers {
                        option("Stickers", "face.smiling", .yellow) { pick(onStickers) }
                    }
                }
                .padding(AppSpacing.xxl)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
    }

    private func option(_ label: String, _ icon: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.18))
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 60, height: 60)
                Text(LocalizedStringKey(label))
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            }
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
