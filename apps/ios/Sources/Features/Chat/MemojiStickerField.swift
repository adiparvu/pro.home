import SwiftUI
import UIKit

// MARK: - iOS sticker capture field
//
// Apple exposes Memoji/emoji-keyboard stickers to apps only through text
// input: a UITextView that accepts image attachments receives the sticker
// the moment the user taps it on the emoji keyboard. This field captures
// that image (NSTextAttachment on iOS 17, NSAdaptiveImageGlyph on iOS 18+),
// hands it to `onPick` and clears itself — turning the system sticker
// drawer into a send-as-image flow.

struct MemojiStickerField: UIViewRepresentable {
    let onPick: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: 34)
        tv.backgroundColor = .clear
        tv.allowsEditingTextAttributes = true
        tv.autocorrectionType = .no
        tv.tintColor = .systemBlue
        if #available(iOS 18.0, *) {
            tv.supportsAdaptiveImageGlyph = true
        }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}

    final class Coordinator: NSObject, UITextViewDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func textViewDidChange(_ textView: UITextView) {
            guard let attributed = textView.attributedText, attributed.length > 0 else { return }
            var picked: UIImage?

            attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, _, stop in
                if #available(iOS 18.0, *),
                   let glyph = attrs[.adaptiveImageGlyph] as? NSAdaptiveImageGlyph,
                   let img = UIImage(data: glyph.imageContent) {
                    picked = img
                    stop.pointee = true
                    return
                }
                if let attachment = attrs[.attachment] as? NSTextAttachment {
                    if let img = attachment.image {
                        picked = img
                        stop.pointee = true
                    } else if let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents,
                              let img = UIImage(data: data) {
                        picked = img
                        stop.pointee = true
                    }
                }
            }

            if let picked {
                textView.text = ""
                onPick(picked)
            }
        }
    }
}
