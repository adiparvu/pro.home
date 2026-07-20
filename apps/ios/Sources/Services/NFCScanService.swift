import Foundation
import CoreNFC
import Observation

/// Why an NDEF write can fail, with user-facing localized descriptions.
/// `.canceled` carries no message — the user closed the sheet themselves.
enum NFCWriteError: LocalizedError {
    case notSupported
    case readOnly
    case capacityTooSmall
    case writeFailed
    case canceled

    var errorDescription: String? {
        switch self {
        case .notSupported:     return String(localized: "This tag does not support NDEF writing.")
        case .readOnly:         return String(localized: "This tag is read-only and cannot be written.")
        case .capacityTooSmall: return String(localized: "The link does not fit in this tag's memory.")
        case .writeFailed:      return String(localized: "Writing failed. Hold the tag still and try again.")
        case .canceled:         return nil
        }
    }
}

@MainActor
@Observable
final class NFCScanService: NSObject {
    static let shared = NFCScanService()

    var lastScannedPayload: String?
    var isScanning = false
    var isWriting = false
    var errorMessage: String?

    private var session: NFCNDEFReaderSession?
    private var onScan: ((String) -> Void)?
    /// Kept alive for the duration of a write session (it is that session's delegate).
    private var writer: NDEFWriter?

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

    // MARK: - NDEF writing

    /// Writes `url` as a well-known NDEF URI record to the next tag held to
    /// the phone. A dedicated delegate object runs the session, so the read
    /// path above (`didDetectNDEFs`) keeps its exact behavior — implementing
    /// `didDetect tags:` on this class would silently disable it.
    func write(url: URL, prompt: String, completion: @escaping @MainActor (Result<Void, NFCWriteError>) -> Void) {
        guard NFCScanService.isSupported else {
            completion(.failure(.notSupported))
            return
        }
        guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
            completion(.failure(.writeFailed))
            return
        }
        isWriting = true
        let writer = NDEFWriter(message: NFCNDEFMessage(records: [payload])) { [weak self] result in
            Task { @MainActor in
                self?.isWriting = false
                self?.writer = nil
                completion(result)
            }
        }
        self.writer = writer
        writer.begin(prompt: prompt)
    }
}

// MARK: - Write session delegate

/// One-shot NDEF writer: detects a tag, checks writability and capacity,
/// writes the message, and reports exactly once.
private final class NDEFWriter: NSObject, NFCNDEFReaderSessionDelegate {
    private let message: NFCNDEFMessage
    private let completion: (Result<Void, NFCWriteError>) -> Void
    private var session: NFCNDEFReaderSession?
    /// Guarded by the session's serial delegate queue.
    private var finished = false

    init(message: NFCNDEFMessage, completion: @escaping (Result<Void, NFCWriteError>) -> Void) {
        self.message = message
        self.completion = completion
        super.init()
    }

    func begin(prompt: String) {
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = prompt
        self.session = session
        session.begin()
    }

    private func finish(_ session: NFCNDEFReaderSession, _ result: Result<Void, NFCWriteError>) {
        guard !finished else { return }
        finished = true
        if case .failure(let error) = result, let message = error.errorDescription {
            session.invalidate(errorMessage: message)
        } else {
            session.invalidate()
        }
        completion(result)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            guard error == nil else { return self.finish(session, .failure(.writeFailed)) }
            tag.queryNDEFStatus { status, capacity, error in
                guard error == nil else { return self.finish(session, .failure(.writeFailed)) }
                switch status {
                case .notSupported:
                    self.finish(session, .failure(.notSupported))
                case .readOnly:
                    self.finish(session, .failure(.readOnly))
                case .readWrite:
                    guard self.message.length <= capacity else {
                        return self.finish(session, .failure(.capacityTooSmall))
                    }
                    tag.writeNDEF(self.message) { error in
                        self.finish(session, error == nil ? .success(()) : .failure(.writeFailed))
                    }
                @unknown default:
                    self.finish(session, .failure(.writeFailed))
                }
            }
        }
    }

    // Required by the protocol; never called once `didDetect tags:` exists.
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        guard !finished else { return }
        finished = true
        // Ending without a write means the user closed the sheet or the
        // session timed out — surface it as a silent cancel, not an error.
        completion(.failure(.canceled))
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
