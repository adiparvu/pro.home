import SwiftUI
import Observation
import WidgetKit

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
    /// Raw [r,g,b] endpoints — the same triplets the widget/watch snapshot
    /// publishes, so every surface derives its Color from ONE source.
    let topRGB: [Double]
    let bottomRGB: [Double]
    /// Dark ground → light on-backdrop text.
    let wantsDark: Bool

    var top: Color { Color(red: topRGB[0], green: topRGB[1], blue: topRGB[2]) }
    var bottom: Color { Color(red: bottomRGB[0], green: bottomRGB[1], blue: bottomRGB[2]) }

    /// The curated set: premium, quiet, deliberately few — a backdrop
    /// gallery, not a wallpaper store.
    static let all: [BackgroundGradientPreset] = [
        .init(id: "aurora",   titleKey: "bg_g_aurora",
              topRGB: [0.07, 0.10, 0.22], bottomRGB: [0.10, 0.32, 0.36], wantsDark: true),
        .init(id: "ocean",    titleKey: "bg_g_ocean",
              topRGB: [0.29, 0.53, 0.78], bottomRGB: [0.80, 0.89, 0.95], wantsDark: false),
        .init(id: "dawn",     titleKey: "bg_g_dawn",
              topRGB: [0.56, 0.52, 0.76], bottomRGB: [0.98, 0.80, 0.67], wantsDark: false),
        .init(id: "graphite", titleKey: "bg_g_graphite",
              topRGB: [0.09, 0.10, 0.12], bottomRGB: [0.22, 0.24, 0.28], wantsDark: true),
        .init(id: "forest",   titleKey: "bg_g_forest",
              topRGB: [0.05, 0.14, 0.11], bottomRGB: [0.22, 0.36, 0.28], wantsDark: true),
        .init(id: "sand",     titleKey: "bg_g_sand",
              topRGB: [0.93, 0.87, 0.77], bottomRGB: [0.83, 0.72, 0.58], wantsDark: false),
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
        static let photoTop = "prvio.background.photoTopRGB"
        static let photoBottom = "prvio.background.photoBottomRGB"
    }

    var mode: AppBackgroundMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode)
                 publishToWidgets() }
    }
    var gradientId: String {
        didSet { UserDefaults.standard.set(gradientId, forKey: Keys.gradient)
                 publishToWidgets() }
    }
    /// Extra darkening over the photo, for text legibility (0…0.5).
    var photoDim: Double {
        didSet { UserDefaults.standard.set(photoDim, forKey: Keys.photoDim)
                 publishToWidgets() }
    }
    private(set) var photo: UIImage?
    private(set) var photoWantsDark: Bool
    /// Average colors of the photo's top/bottom thirds, measured at import —
    /// what widgets and the watch wear when the backdrop is a photo.
    private(set) var photoTopRGB: [Double]
    private(set) var photoBottomRGB: [Double]

    private init() {
        let d = UserDefaults.standard
        mode = AppBackgroundMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .gradient
        gradientId = d.string(forKey: Keys.gradient) ?? "aurora"
        photoDim = d.object(forKey: Keys.photoDim) as? Double ?? 0.18
        photoWantsDark = d.object(forKey: Keys.photoDark) as? Bool ?? true
        photoTopRGB = d.array(forKey: Keys.photoTop) as? [Double] ?? []
        photoBottomRGB = d.array(forKey: Keys.photoBottom) as? [Double] ?? []
        photo = UIImage(contentsOfFile: Self.photoURL.path)
        // The live sky was RETIRED from the page (user-decreed, IMG_8767):
        // a stored liveSky pref migrates to the gradient default. The
        // weather stage's code stays dormant, not deleted.
        if mode == .liveSky { mode = .gradient }
        // A photo mode without its file (fresh install, cleared storage)
        // falls back honestly instead of painting black.
        if mode == .photo && photo == nil { mode = .gradient }
        // Widgets/watch wear the same chosen backdrop from first launch —
        // deferred a tick so the publish never races the singleton's init.
        Task { @MainActor in self.publishToWidgets() }
    }

    var gradient: BackgroundGradientPreset { .preset(id: gradientId) }

    /// The one signal on-backdrop text colors read (AppBackdrop.swift):
    /// does the CURRENT ground want light text? (.liveSky is retired —
    /// init migrates it — but the branch stays honest if it ever returns.)
    var wantsDarkGround: Bool {
        switch mode {
        case .liveSky:  WeatherStageEngine.shared.toParams.snapshotWantsDarkScheme
        case .gradient: gradient.wantsDark
        case .photo:    photoWantsDark
        }
    }

    /// Root color-scheme override (IMG_8763–8769): a CHOSEN static backdrop
    /// dictates the scheme — a dark gradient or photo renders the whole app
    /// dark (white text everywhere), a light one renders it light — exactly
    /// how iOS treats a wallpaper. Without this, a light theme's black
    /// `.primary` text vanished into the Grafit gradient on every screen at
    /// once; no per-screen sweep can fix what the scheme itself gets wrong.
    /// The retired liveSky defers to the theme (nil).
    var preferredScheme: ColorScheme? {
        mode == .liveSky ? nil : (wantsDarkGround ? .dark : .light)
    }

    // MARK: Widgets/Watch mirror (audit 2026-07-21)

    /// Publishes the CHOSEN backdrop's endpoint colors into the App Group so
    /// widgets (directly) and the watch (via the payload) wear the same
    /// ground as the phone. Replaces the retired weather-sky publisher —
    /// a static choice has no TTL: it stays honest until it is changed.
    func publishToWidgets() {
        let top: [Double], bottom: [Double]
        switch mode {
        case .gradient, .liveSky:
            top = gradient.topRGB; bottom = gradient.bottomRGB
        case .photo:
            // The measured thirds, with the readability dim baked in — the
            // widget should match what the phone actually shows.
            let g = BackgroundGradientPreset.preset(id: "graphite")
            let t = photoTopRGB.count == 3 ? photoTopRGB : g.topRGB
            let b = photoBottomRGB.count == 3 ? photoBottomRGB : g.bottomRGB
            top = t.map { $0 * (1.0 - photoDim) }
            bottom = b.map { $0 * (1.0 - photoDim) }
        }
        SharedDataStore.writeBackdropSky(WeatherSkySnapshot(
            top: top, bottom: bottom,
            darkGround: wantsDarkGround, capturedAt: Date()))
        WidgetCenter.shared.reloadAllTimelines()
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
        // decides whether text over this photo goes light or dark, and the
        // top/bottom-third averages become the widget/watch endpoints.
        let luma = stored.map(Self.averageLuma) ?? 0.3
        photoWantsDark = luma * (1.0 - photoDim) < 0.45
        UserDefaults.standard.set(photoWantsDark, forKey: Keys.photoDark)
        if let stored {
            photoTopRGB = Self.averageColor(of: stored, band: .top)
            photoBottomRGB = Self.averageColor(of: stored, band: .bottom)
            UserDefaults.standard.set(photoTopRGB, forKey: Keys.photoTop)
            UserDefaults.standard.set(photoBottomRGB, forKey: Keys.photoBottom)
        }
        mode = .photo
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: Self.photoURL)
        photo = nil
        if mode == .photo { mode = .gradient }
    }

    private static var photoURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("PRVIO/backdrop.jpg")
    }

    /// Average luma via a 1×1 downdraw — the GPU-free way to ask "is this
    /// photo dark?" exactly once, at import.
    private static func averageLuma(_ image: UIImage) -> Double {
        let rgb = averageColor(of: image, band: .full)
        return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]
    }

    private enum PhotoBand { case full, top, bottom }

    /// Average [r,g,b] of a horizontal band, via a 1×1 downdraw of the
    /// band's crop — measured once at import, never per frame.
    private static func averageColor(of image: UIImage, band: PhotoBand) -> [Double] {
        guard var cg = image.cgImage else { return [0.15, 0.16, 0.19] }
        let h = cg.height
        let third = max(h / 3, 1)
        let crop: CGRect? = switch band {
        case .full:   nil
        case .top:    CGRect(x: 0, y: 0, width: cg.width, height: third)
        case .bottom: CGRect(x: 0, y: h - third, width: cg.width, height: third)
        }
        if let crop, let cut = cg.cropping(to: crop) { cg = cut }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1,
                                  bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [0.15, 0.16, 0.19] }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return [Double(pixel[0]) / 255.0, Double(pixel[1]) / 255.0, Double(pixel[2]) / 255.0]
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
