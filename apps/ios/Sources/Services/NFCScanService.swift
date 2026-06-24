import Foundation
import CoreNFC
import Combine

@MainActor
final class NFCScanService: NSObject, ObservableObject {
    static let shared = NFCScanService()

    @Published var lastScannedPayload: String?
    @Published var isScanning = false
    @Published var errorMessage: String?

    private var session: NFCNDEFReaderSession?
    private var onScan: ((String) -> Void)?

    static var isSupported: Bool { NFCNDEFReaderSession.readingAvailable }

    private override init() { super.init() }

    func scan(prompt: String = "Apropie iPhone-ul de tag-ul NFC al echipamentului", onResult: @escaping (String) -> Void) {
        guard NFCScanService.isSupported else {
            errorMessage = "NFC nu este disponibil pe acest dispozitiv."
            return
        }
        onScan = onResult
        isScanning = true
        errorMessage = nil
        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session?.alertMessage = prompt
        session?.begin()
    }
}

extension NFCScanService: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            if (error as? NFCReaderError)?.code != .readerSessionInvalidationErrorFirstNDEFTagRead &&
               (error as? NFCReaderError)?.code != .readerSessionInvalidationErrorUserCanceled {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let payload = messages.first?.records.first.flatMap { record -> String? in
            if let text = String(data: record.payload, encoding: .utf8) { return text }
            if let text = String(data: record.payload.dropFirst(), encoding: .utf8) { return text }
            return record.payload.map { String(format: "%02x", $0) }.joined()
        } ?? "tag-nfc-\(UUID().uuidString.prefix(8))"

        Task { @MainActor in
            self.lastScannedPayload = payload
            self.isScanning = false
            self.onScan?(payload)
        }
    }
}
