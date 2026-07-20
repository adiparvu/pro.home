import SwiftUI
import Observation

// MARK: - Background personalizat (user-decreed, 2026-07-20)
//
// One authority for WHAT the app-wide backdrop is. Three modes:
//  · liveSky  — the F1–F4 procedural weather stage (the default);
//  · gradient — a curated static gradient, always the same, zero GPU work;
//  · photo    — the owner's own photograph, stored on device, with a
//    readability dim and a luminance measured at import so on-backdrop
//    text picks its color from the REAL ground it sits on.
//
// `appBackground` (AppBackdrop.swift) renders `AppBackgroundView`, which
// switches on this authority — the hundreds of existing call sites keep
// working untouched, exactly like every backdrop generation before it.

enum AppBackgroundMode: String, CaseIterable {
    case liveSky, gradient, photo
}

struct BackgroundGradientPreset: Identifiable, Equatable {
    let id: String
    let titleKey: String
    let top: Color
    let bottom: Color
    /// Dark ground → light on-backdrop text.
    let wantsDark: Bool

    /// The curated set: premium, quiet, deliberately few — a backdrop
    /// gallery, not a wallpaper store.
    static let all: [BackgroundGradientPreset] = [
        .init(id: "aurora",   titleKey: "bg_g_aurora",
              top: Color(red: 0.07, green: 0.10, blue: 0.22),
              bottom: Color(red: 0.10, green: 0.32, blue: 0.36), wantsDark: true),
        .init(id: "ocean",    titleKey: "bg_g_ocean",
              top: Color(red: 0.29, green: 0.53, blue: 0.78),
              bottom: Color(red: 0.80, green: 0.89, blue: 0.95), wantsDark: false),
        .init(id: "dawn",     titleKey: "bg_g_dawn",
              top: Color(red: 0.56, green: 0.52, blue: 0.76),
              bottom: Color(red: 0.98, green: 0.80, blue: 0.67), wantsDark: false),
        .init(id: "graphite", titleKey: "bg_g_graphite",
              top: Color(red: 0.09, green: 0.10, blue: 0.12),
              bottom: Color(red: 0.22, green: 0.24, blue: 0.28), wantsDark: true),
        .init(id: "forest",   titleKey: "bg_g_forest",
              top: Color(red: 0.05, green: 0.14, blue: 0.11),
              bottom: Color(red: 0.22, green: 0.36, blue: 0.28), wantsDark: true),
        .init(id: "sand",     titleKey: "bg_g_sand",
              top: Color(red: 0.93, green: 0.87, blue: 0.77),
              bottom: Color(red: 0.83, green: 0.72, blue: 0.58), wantsDark: false),
    ]

    static func preset(id: String) -> BackgroundGradientPreset {
        all.first { $0.id == id } ?? all[0]
    }
}

@MainActor
@Observable
final class BackgroundStyle {
    static let shared = BackgroundStyle()

    private enum Keys {
        static let mode = "prvio.background.mode"
        static let gradient = "prvio.background.gradient"
        static let photoDark = "prvio.background.photoWantsDark"
        static let photoDim = "prvio.background.photoDim"
    }

    var mode: AppBackgroundMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }
    var gradientId: String {
        didSet { UserDefaults.standard.set(gradientId, forKey: Keys.gradient) }
    }
    /// Extra darkening over the photo, for text legibility (0…0.5).
    var photoDim: Double {
        didSet { UserDefaults.standard.set(photoDim, forKey: Keys.photoDim) }
    }
    private(set) var photo: UIImage?
    private(set) var photoWantsDark: Bool

    private init() {
        let d = UserDefaults.standard
        mode = AppBackgroundMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .liveSky
        gradientId = d.string(forKey: Keys.gradient) ?? "aurora"
        photoDim = d.object(forKey: Keys.photoDim) as? Double ?? 0.18
        photoWantsDark = d.object(forKey: Keys.photoDark) as? Bool ?? true
        photo = UIImage(contentsOfFile: Self.photoURL.path)
        // A photo mode without its file (fresh install, cleared storage)
        // falls back honestly instead of painting black.
        if mode == .photo && photo == nil { mode = .liveSky }
    }

    var gradient: BackgroundGradientPreset { .preset(id: gradientId) }

    /// The one signal on-backdrop text colors read (AppBackdrop.swift):
    /// does the CURRENT ground want light text?
    var wantsDarkGround: Bool {
        switch mode {
        case .liveSky:  WeatherStageEngine.shared.toParams.snapshotWantsDarkScheme
        case .gradient: gradient.wantsDark
        case .photo:    photoWantsDark
        }
    }

    // MARK: Photo lifecycle

    func setPhoto(_ image: UIImage) {
        guard let data = image.uploadJPEG(quality: 0.9, maxDimension: 2400) else { return }
        try? FileManager.default.createDirectory(at: Self.photoURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.photoURL, options: .atomic)
        let stored = UIImage(data: data)
        photo = stored
        // Measured once at import: the average luma (with the dim applied)
        // decides whether text over this photo goes light or dark.
        let luma = stored.map(Self.averageLuma) ?? 0.3
        photoWantsDark = luma * (1.0 - photoDim) < 0.45
        UserDefaults.standard.set(photoWantsDark, forKey: Keys.photoDark)
        mode = .photo
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: Self.photoURL)
        photo = nil
        if mode == .photo { mode = .liveSky }
    }

    private static var photoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("PRVIO/backdrop.jpg")
    }

    /// Average luma via a 1×1 downdraw — the GPU-free way to ask "is this
    /// photo dark?" exactly once, at import.
    private static func averageLuma(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0.3 }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0.3 }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1])
              + 0.114 * Double(pixel[2])) / 255.0
    }
}

// MARK: - The switch every screen renders

struct AppBackgroundView: View {
    var body: some View {
        // Reading `shared` inside body keeps Observation tracking live:
        // a mode/preset/photo change repaints every screen instantly.
        let style = BackgroundStyle.shared
        Group {
            switch style.mode {
            case .liveSky:
                WeatherStageView()
            case .gradient:
                LinearGradient(colors: [style.gradient.top, style.gradient.bottom],
                               startPoint: .top, endPoint: .bottom)
            case .photo:
                GeometryReader { geo in
                    if let photo = style.photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .overlay(Color.black.opacity(style.photoDim))
                    } else {
                        LinearGradient(colors: [BackgroundGradientPreset.all[3].top,
                                                BackgroundGradientPreset.all[3].bottom],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
