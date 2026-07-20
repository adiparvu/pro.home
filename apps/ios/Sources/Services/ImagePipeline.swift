import UIKit

// MARK: - Upload-side image sizing
//
// Camera frames are ~4000px on a side. Nothing in the app renders larger
// than ~2560, yet uploads used to ship the full sensor bitmap — paying in
// storage, bandwidth, and worst of all in decode time on every family
// member's device each time a grid scrolls. Downscale once, at the source.

extension UIImage {
    /// JPEG for upload, capped at `maxDimension` on the longest side.
    /// Images already within the cap encode as-is.
    func uploadJPEG(quality: CGFloat, maxDimension: CGFloat = 2560) -> Data? {
        let pixelLongest = max(size.width, size.height) * scale
        guard pixelLongest > maxDimension else {
            return jpegData(compressionQuality: quality)
        }
        let factor = maxDimension / pixelLongest
        let target = CGSize(width: size.width * scale * factor,
                            height: size.height * scale * factor)
        guard let scaled = preparingThumbnail(of: target) else {
            return jpegData(compressionQuality: quality)
        }
        return scaled.jpegData(compressionQuality: quality)
    }
}
