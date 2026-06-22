import Vision
import UIKit

struct ProductScanResult {
    var name: String = ""
    var brand: String = ""
    var model: String = ""
    var serialNumber: String = ""
}

enum VisionCaptureService {

    // Extract raw text lines from an image using on-device OCR.
    static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? handler.perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    }

    // Parse brand/model/serial from a product label or device photo.
    static func parseProduct(from lines: [String]) -> ProductScanResult {
        var result = ProductScanResult()
        let joined = lines.joined(separator: "\n")
        let lower = joined.lowercased()

        // Serial number — common labels
        let serialPatterns = [
            #"s/n[:\s]+([A-Z0-9\-]{4,20})"#,
            #"serial[:\s]+([A-Z0-9\-]{4,20})"#,
            #"sn[:\s]+([A-Z0-9\-]{4,20})"#,
        ]
        for pattern in serialPatterns {
            if let match = joined.firstMatch(pattern: pattern, options: .caseInsensitive) {
                result.serialNumber = match
                break
            }
        }

        // Model number — common labels
        let modelPatterns = [
            #"model[:\s#]+([A-Z0-9\-]{3,20})"#,
            #"mod[.:\s]+([A-Z0-9\-]{3,20})"#,
        ]
        for pattern in modelPatterns {
            if let match = joined.firstMatch(pattern: pattern, options: .caseInsensitive) {
                result.model = match
                break
            }
        }

        // Known brands — pick the first line that matches
        let knownBrands = [
            "Samsung", "LG", "Bosch", "Siemens", "Whirlpool", "Electrolux", "Miele",
            "Indesit", "Beko", "AEG", "Candy", "Hotpoint", "Ariston", "Zanussi",
            "Apple", "Sony", "Philips", "Panasonic", "Gorenje", "Haier", "Hisense",
            "Frigidaire", "GE", "Kenmore", "Maytag", "Bauknecht", "Fagor", "Smeg",
        ]
        for brand in knownBrands {
            if lower.contains(brand.lowercased()) {
                result.brand = brand
                break
            }
        }

        // Name: use first non-empty line that's not a serial/model label
        let skipWords = ["model", "serial", "s/n", "ean", "barcode", "www", "http"]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let tl = trimmed.lowercased()
            guard trimmed.count >= 3,
                  !skipWords.contains(where: { tl.hasPrefix($0) }),
                  trimmed.range(of: #"^\d+$"#, options: .regularExpression) == nil
            else { continue }
            result.name = trimmed
            break
        }

        return result
    }
}

private extension String {
    func firstMatch(pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: self)
        else { return nil }
        return String(self[captureRange])
    }
}
