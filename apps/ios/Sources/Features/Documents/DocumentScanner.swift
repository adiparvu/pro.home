import SwiftUI
import VisionKit
import Vision
import UIKit

// MARK: - Native document scanner (VisionKit)
//
// The system's document camera: multi-page capture with automatic edge
// detection and perspective correction. The scan becomes a single PDF and
// the first pages run through Vision OCR to propose a title and — the part
// that matters for this app — detect an EXPIRY DATE, so a scanned insurance
// policy arrives with its renewal reminder already set.

struct DocumentScanResult {
    let pdfData: Data
    let pageCount: Int
    var suggestedName: String?
    var suggestedExpiry: Date?
}

struct DocumentScannerView: UIViewControllerRepresentable {
    /// nil on cancel or failure — the caller simply stays where it was.
    let onFinish: (DocumentScanResult?) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (DocumentScanResult?) -> Void
        init(onFinish: @escaping (DocumentScanResult?) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true)
            Task.detached(priority: .userInitiated) {
                let result = DocumentScanIntelligence.process(pages: images)
                await MainActor.run { [onFinish] in onFinish(result) }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onFinish(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onFinish(nil)
        }
    }
}

// MARK: - PDF assembly + expiry intelligence

enum DocumentScanIntelligence {

    static func process(pages: [UIImage]) -> DocumentScanResult? {
        guard !pages.isEmpty, let pdf = makePDF(pages: pages) else { return nil }
        // OCR only the first two pages — expiry and title live up front, and
        // a 10-page manual shouldn't cost 10 OCR passes.
        let lines = pages.prefix(2).flatMap { recognizeLines(in: $0) }
        return DocumentScanResult(pdfData: pdf,
                                  pageCount: pages.count,
                                  suggestedName: suggestName(from: lines),
                                  suggestedExpiry: detectExpiry(in: lines))
    }

    private static func makePDF(pages: [UIImage]) -> Data? {
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        let data = renderer.pdfData { context in
            for page in pages {
                let bounds = CGRect(origin: .zero, size: page.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                page.draw(in: bounds)
            }
        }
        return data.isEmpty ? nil : data
    }

    private static func recognizeLines(in image: UIImage) -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ro-RO", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// The first substantial line that isn't mostly digits — document titles
    /// sit at the top; serial numbers and dates don't make good names.
    static func suggestName(from lines: [String]) -> String? {
        for line in lines.prefix(8) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 4, trimmed.count <= 60 else { continue }
            let digits = trimmed.filter(\.isNumber).count
            guard digits < trimmed.count / 2 else { continue }
            return trimmed
        }
        return nil
    }

    /// Finds the expiry: a date on a line with an expiry keyword wins; with
    /// no keyword, the latest FUTURE date in the document is the best guess.
    /// Past dates are issue/birth dates — never proposed as expiry.
    static func detectExpiry(in lines: [String]) -> Date? {
        let keywords = ["valabil", "expir", "valid", "until", "până", "pana",
                        "scaden", "renewal", "reînnoire"]
        var keywordDates: [Date] = []
        var allFutureDates: [Date] = []
        let now = Date()

        for line in lines {
            let lower = line.lowercased()
            let dates = extractDates(from: line)
            let future = dates.filter { $0 > now }
            allFutureDates.append(contentsOf: future)
            if keywords.contains(where: { lower.contains($0) }) {
                keywordDates.append(contentsOf: future)
            }
        }
        return keywordDates.max() ?? allFutureDates.max()
    }

    /// dd.MM.yyyy, dd/MM/yyyy, dd-MM-yyyy and yyyy-MM-dd, anywhere in a line.
    static func extractDates(from text: String) -> [Date] {
        var found: [Date] = []
        for match in text.matches(of: #/(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{4})/#) {
            found.append(contentsOf: date(day: Int(match.1), month: Int(match.2), year: Int(match.3)))
        }
        for match in text.matches(of: #/(\d{4})-(\d{2})-(\d{2})/#) {
            found.append(contentsOf: date(day: Int(match.3), month: Int(match.2), year: Int(match.1)))
        }
        return found
    }

    private static func date(day: Int?, month: Int?, year: Int?) -> [Date] {
        guard let day, let month, let year,
              (1...31).contains(day), (1...12).contains(month), (2000...2100).contains(year) else { return [] }
        var components = DateComponents()
        components.day = day; components.month = month; components.year = year
        components.hour = 12
        return Calendar.current.date(from: components).map { [$0] } ?? []
    }
}
