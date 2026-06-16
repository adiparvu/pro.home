import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeImage: View {
    let content: String
    var size: CGFloat = 200

    private var image: UIImage? {
        guard let data = content.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        if let img = image {
            Image(uiImage: img)
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: size, height: size)
                .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.08)).frame(width: size, height: size)
        }
    }
}
