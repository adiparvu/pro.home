import UIKit
import Observation

// MARK: - Camera fetch errors

/// Why a snapshot fetch failed — surfaced verbatim by the "Test connection"
/// button so the user can tell a typo'd URL from wrong credentials.
enum CameraFetchError: Error {
    case invalidURL
    case unauthorized
    case http(Int)
    case notAnImage
    case network

    var localizedMessage: String {
        switch self {
        case .invalidURL:   return String(localized: "cameras_err_invalid_url")
        case .unauthorized: return String(localized: "cameras_err_auth")
        case .http(let code):
            return String(format: String(localized: "cameras_err_http"), code)
        case .notAnImage:   return String(localized: "cameras_err_not_image")
        case .network:      return String(localized: "cameras_err_network")
        }
    }
}

// MARK: - CameraService
//
// Owns the RTSP camera list (device-local, see CameraModels.swift) and the
// snapshot pipeline: honest still-image polling over the cameras' HTTP
// snapshot endpoints — never presented as continuous video. Polling runs
// ONLY while the Cameras page is on screen (start/stop from onAppear /
// onDisappear) — the battery rule.

@MainActor
@Observable
final class CameraService {
    static let shared = CameraService()

    private(set) var cameras: [SecurityCamera]
    /// Latest successfully fetched frame per camera, with its capture time —
    /// the grid renders from here and derives staleness from `at`.
    private(set) var latest: [UUID: (image: UIImage, at: Date)] = [:]

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    private init() {
        cameras = CameraStore.load()
    }

    // MARK: - CRUD (password → Keychain only)

    private static func secretKey(_ id: UUID) -> String { "camera.\(id.uuidString)" }

    func password(forCameraId id: UUID) -> String {
        SecretStore.string(for: Self.secretKey(id))
    }

    func add(_ camera: SecurityCamera, password: String) {
        cameras.append(camera)
        CameraStore.save(cameras)
        SecretStore.set(password, for: Self.secretKey(camera.id))
    }

    func update(_ camera: SecurityCamera, password: String) {
        guard let idx = cameras.firstIndex(where: { $0.id == camera.id }) else { return }
        cameras[idx] = camera
        CameraStore.save(cameras)
        SecretStore.set(password, for: Self.secretKey(camera.id))
    }

    func delete(_ camera: SecurityCamera) {
        cameras.removeAll { $0.id == camera.id }
        CameraStore.save(cameras)
        latest[camera.id] = nil
        // SecretStore deletes the Keychain item when handed an empty value.
        SecretStore.set("", for: Self.secretKey(camera.id))
    }

    // MARK: - Snapshot fetch

    /// Fetches one still frame and, on success, records it in `latest`.
    @discardableResult
    func snapshot(for camera: SecurityCamera) async -> UIImage? {
        let result = await Self.fetch(urlString: camera.snapshotURL,
                                      username: camera.username ?? "",
                                      password: password(forCameraId: camera.id))
        guard case .success(let image) = result else { return nil }
        latest[camera.id] = (image, Date())
        return image
    }

    /// One-off fetch used by the form's "Test connection" button (the camera
    /// may not be saved yet, so credentials are passed explicitly).
    nonisolated static func fetch(urlString: String,
                                  username: String,
                                  password: String) async -> Result<UIImage, CameraFetchError> {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return .failure(.invalidURL) }

        // Hikvision/Dahua default to HTTP Digest auth; some firmwares use
        // Basic. Both arrive as a URLAuthenticationChallenge, which the
        // delegate answers with one URLCredential — URLSession then performs
        // the correct Basic or Digest handshake itself. Server-trust (TLS)
        // challenges keep default handling: certificate validation is never
        // weakened.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config,
                                 delegate: CameraAuthDelegate(username: username, password: password),
                                 delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .failure(.network) }
            if http.statusCode == 401 || http.statusCode == 403 { return .failure(.unauthorized) }
            guard (200..<300).contains(http.statusCode) else { return .failure(.http(http.statusCode)) }
            guard let image = UIImage(data: data) else { return .failure(.notAnImage) }
            return .success(image)
        } catch let error as URLError where error.code == .cancelled || error.code == .userAuthenticationRequired {
            // The delegate cancels the request after a failed credential
            // round-trip — that's an auth problem, not a network one.
            return .failure(.unauthorized)
        } catch {
            return .failure(.network)
        }
    }

    // MARK: - Polling (page-visible only)

    /// Refreshes every camera's frame on a fixed cadence. Idempotent —
    /// calling it while a loop is already running is a no-op.
    func startPolling(interval: TimeInterval = 4) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Fetches all cameras concurrently; slow or offline cameras never delay
    /// the others.
    func refreshAll() async {
        let snapshotJobs = cameras.map { cam in
            (id: cam.id,
             url: cam.snapshotURL,
             user: cam.username ?? "",
             pass: password(forCameraId: cam.id))
        }
        guard !snapshotJobs.isEmpty else { return }
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for job in snapshotJobs {
                group.addTask {
                    if case .success(let image) = await CameraService.fetch(
                        urlString: job.url, username: job.user, password: job.pass) {
                        return (job.id, image)
                    }
                    return (job.id, nil)
                }
            }
            for await (id, image) in group {
                if let image { latest[id] = (image, Date()) }
            }
        }
    }
}

// MARK: - Auth delegate (Basic + Digest)

private final class CameraAuthDelegate: NSObject, URLSessionTaskDelegate {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPBasic
                || method == NSURLAuthenticationMethodHTTPDigest else {
            // Everything else — including ServerTrust — keeps the system's
            // default handling, so TLS validation is never disabled.
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // One attempt: if the camera rejected our credential once, retrying
        // with the same one only locks accounts on some firmwares.
        guard challenge.previousFailureCount == 0,
              !(username.isEmpty && password.isEmpty) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential,
                          URLCredential(user: username, password: password, persistence: .forSession))
    }
}
