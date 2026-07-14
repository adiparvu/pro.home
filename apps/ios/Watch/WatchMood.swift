import SwiftUI

// MARK: - The app's mood, on the wrist
//
// The iPhone resolves the app's living mood (dimineața / zi / apus / noapte /
// ploaie / iarnă / eveniment) and — once `WatchPayload` carries a `mood` field
// (a frozen-file addition owned by the lead; see the probe below) — the raw
// value rides the SAME snapshot push the wrist already lives on. This file is
// the watch's whole mood vocabulary. Raw values this build doesn't know
// (a future mood) decode to nil, and the pages keep their plain tints.
//
// Palette provenance: `AppMoodPalette` in Sources/Components/DesignSystem.swift
// is the single source of truth for every mood color. DesignSystem.swift does
// NOT compile into the watch target, so the hue/opacity pairs below are
// mirrored from it by hand — if a palette changes there, update these values.
//
// Adaptive, not copied: watchOS renders on OLED black and every system style
// assumes a dark ground, so the wrist takes each mood's HUE, not its
// lightness — the palette's two ambient accent colors (at the palette's own
// accent opacities) become the page wash, exactly the liquid the pages
// already pour under themselves. The iPhone's light morning/day grounds
// would fight the watch's dark text styles, so they deliberately stay home.
//
// Honesty: no mood in the payload → no mood on the wrist; every page keeps
// exactly its current tint. A mood that does arrive is the snapshot's mood —
// the same freshness as every other number on the watch, never claimed as
// more live than that.

enum WatchMood: String {
    case morning, day, sunset, night, rain, winter, event

    /// The page wash: top accent → bottom accent, vertical, at the
    /// palette's own accent opacities. Values from AppMoodPalette:
    /// - morning: gold #EFBE8B @ 0.32, rose #E3A29D @ 0.20
    /// - day:     sky #BED7ED @ 0.22, sand #EBDCC0 @ 0.20
    /// - sunset:  ember #E8975A @ 0.26, violet #9B7BB8 @ 0.16
    /// - night:   ember #C98B52 @ 0.10, mauve #6E4E63 @ 0.12
    /// - rain:    slate #7A93AC @ 0.22, teal #7FB0A8 @ 0.16
    /// - winter:  ice #BFE0F0 @ 0.30, silver #D7DEE5 @ 0.26
    /// - event:   gold #E3B354 @ 0.12, magenta #C2478F @ 0.10
    var pageWash: LinearGradient {
        let top: Color, topOpacity: Double
        let bottom: Color, bottomOpacity: Double
        switch self {
        case .morning:
            top = Color(red: 0.937, green: 0.745, blue: 0.545); topOpacity = 0.32
            bottom = Color(red: 0.890, green: 0.635, blue: 0.616); bottomOpacity = 0.20
        case .day:
            top = Color(red: 0.745, green: 0.843, blue: 0.929); topOpacity = 0.22
            bottom = Color(red: 0.922, green: 0.863, blue: 0.753); bottomOpacity = 0.20
        case .sunset:
            top = Color(red: 0.910, green: 0.592, blue: 0.353); topOpacity = 0.26
            bottom = Color(red: 0.608, green: 0.482, blue: 0.722); bottomOpacity = 0.16
        case .night:
            top = Color(red: 0.788, green: 0.545, blue: 0.322); topOpacity = 0.10
            bottom = Color(red: 0.431, green: 0.306, blue: 0.388); bottomOpacity = 0.12
        case .rain:
            top = Color(red: 0.478, green: 0.576, blue: 0.675); topOpacity = 0.22
            bottom = Color(red: 0.498, green: 0.690, blue: 0.659); bottomOpacity = 0.16
        case .winter:
            top = Color(red: 0.749, green: 0.878, blue: 0.941); topOpacity = 0.30
            bottom = Color(red: 0.843, green: 0.871, blue: 0.898); bottomOpacity = 0.26
        case .event:
            top = Color(red: 0.890, green: 0.702, blue: 0.329); topOpacity = 0.12
            bottom = Color(red: 0.761, green: 0.278, blue: 0.561); bottomOpacity = 0.10
        }
        return LinearGradient(colors: [top.opacity(topOpacity),
                                       bottom.opacity(bottomOpacity)],
                              startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Payload probe

extension WatchMood {
    /// Decodes ONLY the mood field out of a WatchPayload JSON blob.
    /// `WatchPayload` itself (Sources/Services/SharedDataStore.swift, frozen)
    /// does not declare the field yet; this probe starts reading it the
    /// moment the phone starts sending it — and returns nil until then, so
    /// the watch never invents a mood. Unknown raw values also map to nil.
    static func fromPayloadData(_ data: Data) -> WatchMood? {
        struct Probe: Decodable { var mood: String? }
        guard let raw = (try? JSONDecoder().decode(Probe.self, from: data))?.mood else {
            return nil
        }
        return WatchMood(rawValue: raw)
    }
}

// MARK: - Environment plumbing

private struct WatchMoodKey: EnvironmentKey {
    static let defaultValue: WatchMood? = nil
}

extension EnvironmentValues {
    /// The mood delivered with the current payload, injected once at the
    /// root so every page's ground reads the same atmosphere.
    var watchMood: WatchMood? {
        get { self[WatchMoodKey.self] }
        set { self[WatchMoodKey.self] = newValue }
    }
}

// MARK: - Page ground

extension View {
    /// The navigation container ground: the mood's ambient wash when the
    /// phone delivered one with the snapshot, else exactly the page's own
    /// tint — today's look, unchanged. (The Emergency page never adopts the
    /// mood: its red ground is a signal, not an atmosphere.)
    func moodPageGround(fallback: Color, opacity: Double) -> some View {
        modifier(MoodPageGround(fallback: fallback, fallbackOpacity: opacity))
    }
}

private struct MoodPageGround: ViewModifier {
    let fallback: Color
    let fallbackOpacity: Double
    @Environment(\.watchMood) private var mood

    @ViewBuilder
    func body(content: Content) -> some View {
        if let mood {
            content.containerBackground(mood.pageWash, for: .navigation)
        } else {
            content.containerBackground(fallback.gradient.opacity(fallbackOpacity),
                                         for: .navigation)
        }
    }
}
