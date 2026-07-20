import SwiftUI
import VisionKit

// MARK: - Barcode capture for the document form (D7 follow-up)
//
// The barcode field existed with its glyph and OCR/keyboard entry, but no
// camera capture despite VisionKit already being in the app. This is the
// missing piece: a DataScanner locked to barcode symbologies that returns the
// first recognized payload and closes — no tap needed, WhatsApp-style.
//
// The scan button only renders when `isSupported` is true (hardware + camera
// authorization not denied), so unsupported devices never see a dead control.
struct DocumentBarcodeScanner: UIViewControllerRepresentable {
    /// Called once with the first recognized barcode payload.
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Whether this device can scan at all — gates the button's existence.
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let dismiss: () -> Void

        init(onScan: @escaping (String) -> Void, dismiss: @escaping () -> Void) {
            self.onScan = onScan
            self.dismiss = dismiss
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in added {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue, !payload.isEmpty {
                    scanner.stopScanning()
                    HapticFeedback.success()
                    onScan(payload)
                    dismiss()
                    return
                }
            }
        }
    }
}
