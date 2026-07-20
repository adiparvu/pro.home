// Camera picker and starred list for the DM screen (split from
// DirectMessageView).
import SwiftUI
import PhotosUI
import UIKit
import Supabase

// MARK: - Camera Picker (UIKit bridge)

struct DMCameraPickerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: DMCameraPickerView
        init(_ parent: DMCameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            DispatchQueue.main.async {
                if let img { self.parent.onCapture(img) }
                self.parent.isPresented = false
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async { self.parent.isPresented = false }
        }
    }
}

// (DMAttachmentOption is gone — the legacy two-icon tray it served was
// unreachable once the iMessage "+" menu (ChatAttachmentSheet) took over, and
// the shared ChatComposerBar has no tray at all.)

// MARK: - DM Starred (marked) messages

struct DMStarredView: View {
    let messages: [DirectMessage]
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private func snippet(_ m: DirectMessage) -> String {
        // The shared DM snippet, so a starred rich payload (location/sticker/
        // event/file/contact) shows its label instead of the raw marker this
        // copy used to leak.
        m.previewSnippet
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                if messages.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "flag.slash")
                            .font(AppFont.scaled(44))
                            .foregroundStyle(Color.primary.opacity(0.18))
                        Text("No starred messages")
                            .font(AppFont.scaled(17, weight: .semibold))
                        Text("Mark a message to find it here later.")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 40)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { msg in
                                Button {
                                    onSelect(msg.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "flag.fill")
                                            .font(AppFont.scaled(13))
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(msg.senderName)
                                                .font(AppFont.captionEmphasis)
                                                .foregroundStyle(.primary)
                                            Text(snippet(msg))
                                                .font(AppFont.scaled(14))
                                                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                                .lineLimit(2)
                                            Text(msg.timeDisplay)
                                                .font(AppFont.scaled(11))
                                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(AppFont.captionStrong)
                                            .foregroundStyle(Color.primary.opacity(0.25))
                                    }
                                    .padding(AppSpacing.base)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(AppSpacing.lg)
                    }
                }
            }
            .navigationTitle("Starred messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }
}
