import SwiftUI
import RoomPlan

/// Entry point for LiDAR room scanning. Falls back to an explanatory screen on
/// devices without LiDAR (RoomPlan is unsupported there).
struct RoomScanView: View {
    let onComplete: (URL?) -> Void

    var body: some View {
        if RoomCaptureSession.isSupported {
            RoomScanContainer(onComplete: onComplete)
                .ignoresSafeArea()
        } else {
            UnsupportedScanView(onClose: { onComplete(nil) })
        }
    }
}

private struct UnsupportedScanView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.3))
                Text("3D Scanning Needs LiDAR")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                Text("This device doesn't have a LiDAR sensor. 3D room capture is available on iPhone Pro and iPad Pro models. You can still add floor plans, blueprints, and photos.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Close") { onClose() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(.white.opacity(0.12), in: Capsule())
                    .padding(.top, 8)
            }
        }
    }
}

private struct RoomScanContainer: UIViewControllerRepresentable {
    let onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> RoomScanController {
        let controller = RoomScanController()
        controller.onComplete = onComplete
        return controller
    }

    func updateUIViewController(_ controller: RoomScanController, context: Context) {}
}

final class RoomScanController: UIViewController, RoomCaptureViewDelegate {
    var onComplete: ((URL?) -> Void)?

    private var roomCaptureView: RoomCaptureView!
    private var config = RoomCaptureSession.Configuration()
    private var finalRoom: CapturedRoom?
    private var isFinishing = false

    private let finishButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        roomCaptureView.delegate = self
        view.addSubview(roomCaptureView)

        setupOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        roomCaptureView.captureSession.run(configuration: config)
    }

    private func setupOverlay() {
        // Hint
        hintLabel.text = "Move slowly around the room to capture walls, doors and windows."
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textColor = .white
        hintLabel.numberOfLines = 0
        hintLabel.textAlignment = .center
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        hintLabel.layer.cornerRadius = 12
        hintLabel.layer.masksToBounds = true
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)

        // Cancel
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        cancelButton.layer.cornerRadius = 20
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        // Finish
        finishButton.setTitle("Finish Scan", for: .normal)
        finishButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        finishButton.setTitleColor(.white, for: .normal)
        finishButton.backgroundColor = UIColor.systemBlue
        finishButton.layer.cornerRadius = 28
        finishButton.translatesAutoresizingMaskIntoConstraints = false
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        view.addSubview(finishButton)

        // Spinner
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 70),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            hintLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cancelButton.widthAnchor.constraint(equalToConstant: 92),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),

            finishButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            finishButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            finishButton.widthAnchor.constraint(equalToConstant: 200),
            finishButton.heightAnchor.constraint(equalToConstant: 56),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func cancelTapped() {
        roomCaptureView.captureSession.stop()
        onComplete?(nil)
    }

    @objc private func finishTapped() {
        guard !isFinishing else { return }
        isFinishing = true
        finishButton.isHidden = true
        cancelButton.isHidden = true
        hintLabel.text = "Processing 3D model…"
        spinner.startAnimating()
        roomCaptureView.captureSession.stop()
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        finalRoom = processedResult
        if isFinishing { exportAndFinish() }
    }

    private func exportAndFinish() {
        spinner.stopAnimating()
        guard let room = finalRoom else { onComplete?(nil); return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString).usdz")
        do {
            try room.export(to: url)
            onComplete?(url)
        } catch {
            onComplete?(nil)
        }
    }
}
