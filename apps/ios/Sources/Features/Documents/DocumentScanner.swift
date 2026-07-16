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
    /// The recognized text from the first pages, so the caller can run the
    /// full D2 prefill (issuer, amount, identifiers) — not just name + expiry.
    var lines: [String] = []
}

// The camera is presented NATIVELY (a UIKit full-screen modal from an
// invisible host), never embedded as a hosted subview inside a SwiftUI
// cover. VisionKit wires its bottom camera controls (flash / filters /
// shutter mode) to its own presentation environment; hosting the controller
// as a representable's view left those exact buttons dead on iOS 26
// (IMG_8509) while capture itself kept working.
struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    /// nil on cancel or failure — the caller simply stays where it was.
    /// Called only after the camera has fully dismissed, so presenting a
    /// follow-up sheet from inside the callback is safe.
    let onFinish: (DocumentScanResult?) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.onFinish = onFinish
        if isPresented, context.coordinator.camera == nil {
            let camera = VNDocumentCameraViewController()
            camera.delegate = context.coordinator
            camera.modalPresentationStyle = .fullScreen
            context.coordinator.camera = camera
            // Present from the host's nearest presentation context — the
            // exact modal environment VisionKit is built and tested against.
            // Deferred one hop: presenting inside SwiftUI's update pass is
            // an update-during-update hazard.
            DispatchQueue.main.async { [weak host] in
                host?.present(camera, animated: true)
            }
        } else if !isPresented, let camera = context.coordinator.camera {
            context.coordinator.camera = nil
            camera.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var isPresented: Binding<Bool>?
        var onFinish: ((DocumentScanResult?) -> Void)?
        var camera: VNDocumentCameraViewController?

        /// Dismisses the camera, resets the binding, and delivers the result
        /// AFTER the dismissal completes — a follow-up sheet presented from
        /// the callback is never swallowed by an in-flight dismissal.
        private func close(with result: DocumentScanResult?,
                           from controller: VNDocumentCameraViewController) {
            camera = nil
            isPresented?.wrappedValue = false
            let finish = onFinish
            controller.dismiss(animated: true) {
                finish?(result)
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            camera = nil
            isPresented?.wrappedValue = false
            let finish = onFinish
            // OCR + PDF assembly off-main while the camera animates away; the
            // result is delivered on the main actor afterwards.
            controller.dismiss(animated: true) {
                Task.detached(priority: .userInitiated) {
                    let result = DocumentScanIntelligence.process(pages: images)
                    await MainActor.run { finish?(result) }
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            close(with: nil, from: controller)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            close(with: nil, from: controller)
        }
    }
}

extension View {
    /// Presents the system document scanner as a NATIVE full-screen modal
    /// while `isPresented` is true. `onFinish` receives nil on cancel/failure
    /// and fires only after the camera is fully gone.
    func documentScanner(isPresented: Binding<Bool>,
                         onFinish: @escaping (DocumentScanResult?) -> Void) -> some View {
        background(DocumentScannerView(isPresented: isPresented, onFinish: onFinish))
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
                                  suggestedExpiry: detectExpiry(in: lines),
                                  lines: lines)
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
