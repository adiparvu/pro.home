import SwiftUI
import UIKit
import PhotosUI

// MARK: - Chat theme (conversation background + bubble color)

// MARK: - Custom chat wallpaper storage
//
// A user-uploaded chat background. Only the file name is persisted (not the
// absolute path, which can change between app launches); the full URL is
// reconstructed under the app's Documents directory on read.
enum ChatBackgroundStore {
    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static func url(for fileName: String) -> URL? {
        fileName.isEmpty ? nil : dir.appendingPathComponent(fileName)
    }

    /// Decoded wallpapers, keyed by file name. The chat re-evaluates its body
    /// constantly (typing, presence, scroll) and the background used to hit
    /// `UIImage(contentsOfFile:)` — a synchronous main-thread JPEG decode —
    /// on every single pass, which read as a heavy entry stutter.
    private static let decoded = NSCache<NSString, UIImage>()

    /// The wallpaper image for a stored file name, decoded once and cached.
    static func image(named fileName: String) -> UIImage? {
        if let hit = decoded.object(forKey: fileName as NSString) { return hit }
        guard let url = url(for: fileName),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        decoded.setObject(img, forKey: fileName as NSString)
        return img
    }

    /// Persist an image for the given scope and return the stored file name.
    static func save(_ image: UIImage, scope: String?) -> String? {
        let safe = (scope ?? "global").replacingOccurrences(of: "/", with: "_")
        let name = "chatbg-\(safe).jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: dir.appendingPathComponent(name))
            // The name is scope-stable, so a re-upload must drop the old decode.
            decoded.removeObject(forKey: name as NSString)
            return name
        } catch { return nil }
    }
}

struct ChatTheme: Identifiable {
    let id: String
    let name: String
    let outgoingBubble: Color
    let backgroundColors: [Color]?   // nil = app default background
    let isDark: Bool
    var backgroundImage: String? = nil   // custom wallpaper file name (wins over colors)
    var backgroundAnimation: String? = nil   // dynamic preset id (photo wins over it)

    static let all: [ChatTheme] = [
        ChatTheme(id: "appDefault", name: "Default",
                  outgoingBubble: .accentColor, backgroundColors: nil, isDark: false),
        ChatTheme(id: "dark", name: "Dark",
                  outgoingBubble: Color(red: 0.13, green: 0.69, blue: 0.30),
                  backgroundColors: [.black, Color(white: 0.07)], isDark: true),
        ChatTheme(id: "paper", name: "Paper",
                  outgoingBubble: Color(red: 0.13, green: 0.69, blue: 0.30),
                  backgroundColors: [Color(red: 0.96, green: 0.94, blue: 0.88),
                                     Color(red: 0.92, green: 0.89, blue: 0.81)], isDark: false),
        ChatTheme(id: "ocean", name: "Ocean",
                  outgoingBubble: Color(red: 0.0, green: 0.48, blue: 0.66),
                  backgroundColors: [Color(red: 0.78, green: 0.90, blue: 0.95),
                                     Color(red: 0.60, green: 0.79, blue: 0.88)], isDark: false),
        ChatTheme(id: "sunset", name: "Sunset",
                  outgoingBubble: Color(red: 0.90, green: 0.42, blue: 0.28),
                  backgroundColors: [Color(red: 0.99, green: 0.86, blue: 0.70),
                                     Color(red: 0.98, green: 0.70, blue: 0.52)], isDark: false),
        ChatTheme(id: "lavender", name: "Lavender",
                  outgoingBubble: Color(red: 0.45, green: 0.35, blue: 0.85),
                  backgroundColors: [Color(red: 0.86, green: 0.83, blue: 0.97),
                                     Color(red: 0.77, green: 0.73, blue: 0.95)], isDark: false),
        ChatTheme(id: "rose", name: "Rose",
                  outgoingBubble: Color(red: 0.82, green: 0.35, blue: 0.55),
                  backgroundColors: [Color(red: 0.98, green: 0.86, blue: 0.91),
                                     Color(red: 0.96, green: 0.77, blue: 0.85)], isDark: false),
        ChatTheme(id: "holographic", name: "Holographic",
                  outgoingBubble: Color(red: 0.36, green: 0.30, blue: 0.80),
                  backgroundColors: [Color(red: 0.82, green: 0.80, blue: 0.97),
                                     Color(red: 0.92, green: 0.83, blue: 0.95)], isDark: false),
        ChatTheme(id: "coral", name: "Coral",
                  outgoingBubble: Color(red: 0.62, green: 0.27, blue: 0.62),
                  backgroundColors: [Color(red: 0.98, green: 0.80, blue: 0.78),
                                     Color(red: 0.96, green: 0.66, blue: 0.72)], isDark: false),
        ChatTheme(id: "amber", name: "Amber",
                  outgoingBubble: Color(red: 0.80, green: 0.40, blue: 0.30),
                  backgroundColors: [Color(red: 0.99, green: 0.82, blue: 0.55),
                                     Color(red: 0.97, green: 0.62, blue: 0.40)], isDark: false),
        ChatTheme(id: "saltflat", name: "Salt Flat",
                  outgoingBubble: Color(red: 0.13, green: 0.45, blue: 0.36),
                  backgroundColors: [Color(red: 0.62, green: 0.80, blue: 0.86),
                                     Color(red: 0.95, green: 0.75, blue: 0.78)], isDark: false),
        ChatTheme(id: "midnight", name: "Midnight",
                  outgoingBubble: Color(red: 0.20, green: 0.40, blue: 0.90),
                  backgroundColors: [Color(red: 0.05, green: 0.08, blue: 0.18),
                                     Color(red: 0.10, green: 0.13, blue: 0.28)], isDark: true),
    ]

    static func theme(for id: String) -> ChatTheme { all.first { $0.id == id } ?? all[0] }

    /// Resolves the effective theme from the saved theme id plus optional
    /// per-user customizations (custom bubble colour, custom background,
    /// dynamic wallpaper). A photo wins over a dynamic preset, which wins
    /// over a static gradient.
    static func resolved(themeID: String, bubbleHex: String, bgID: String,
                         bgImage: String = "", bgAnim: String = "") -> ChatTheme {
        let base = theme(for: themeID)
        let bubble: Color = (!bubbleHex.isEmpty ? Color(hex: bubbleHex) : nil) ?? base.outgoingBubble
        let bgTheme = bgID.isEmpty ? base : theme(for: bgID)
        let animPreset = bgImage.isEmpty ? AnimatedBackgroundPreset.preset(for: bgAnim) : nil
        let isPlainDefault = themeID == "appDefault" && bubbleHex.isEmpty
            && bgID.isEmpty && bgImage.isEmpty && bgAnim.isEmpty
        return ChatTheme(
            id: isPlainDefault ? "appDefault" : "custom",
            name: base.name,
            outgoingBubble: bubble,
            backgroundColors: bgTheme.backgroundColors,
            isDark: animPreset?.isDark ?? bgTheme.isDark,
            backgroundImage: bgImage.isEmpty ? nil : bgImage,
            backgroundAnimation: animPreset?.id
        )
    }

    /// The one authority for what a conversation actually shows.
    ///
    /// `scope == nil` resolves the global default. For a conversation scope,
    /// THEME and BUBBLE fall back per-field to the global values, but the
    /// three BACKGROUND keys are one setting: the picker clears the other two
    /// ("" = explicitly none) when one is chosen, so a per-field fallback
    /// would resurrect a stale global photo over a freshly picked preset —
    /// the "background never changes" bug. If ANY scoped background key is
    /// set, the scoped background layer wins wholesale.
    static func effective(scope: String?, defaults d: UserDefaults = .standard) -> ChatTheme {
        func nonEmpty(_ key: String) -> String? {
            d.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
        }
        let gTheme = nonEmpty("prvio.chatTheme") ?? "appDefault"
        let gBubble = nonEmpty("prvio.chatBubbleHex") ?? ""
        var bg = nonEmpty("prvio.chatBgID") ?? ""
        var img = nonEmpty("prvio.chatBgImage") ?? ""
        var anim = nonEmpty("prvio.chatBgAnim") ?? ""
        var theme = gTheme
        var bubble = gBubble
        if let scope {
            theme = nonEmpty("prvio.chatTheme.\(scope)") ?? gTheme
            bubble = nonEmpty("prvio.chatBubbleHex.\(scope)") ?? gBubble
            let sBg = d.string(forKey: "prvio.chatBgID.\(scope)") ?? ""
            let sImg = d.string(forKey: "prvio.chatBgImage.\(scope)") ?? ""
            let sAnim = d.string(forKey: "prvio.chatBgAnim.\(scope)") ?? ""
            if !(sBg.isEmpty && sImg.isEmpty && sAnim.isEmpty) {
                bg = sBg; img = sImg; anim = sAnim
            }
        }
        return .resolved(themeID: theme, bubbleHex: bubble, bgID: bg,
                         bgImage: img, bgAnim: anim)
    }

    @ViewBuilder var background: some View {
        if let name = backgroundImage,
           let img = ChatBackgroundStore.image(named: name) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                // Photos arrive raw; the stock themes are designed gradients.
                // A vertical scrim makes wallpapers read like part of the set:
                // stronger where the header and compose bar live, lighter in
                // the middle where the bubbles carry their own contrast.
                .overlay(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.28), location: 0),
                        .init(color: .black.opacity(0.10), location: 0.25),
                        .init(color: .black.opacity(0.10), location: 0.72),
                        .init(color: .black.opacity(0.30), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                )
        } else if let animID = backgroundAnimation,
                  let preset = AnimatedBackgroundPreset.preset(for: animID) {
            AnimatedChatBackground(preset: preset).ignoresSafeArea()
        } else if let cols = backgroundColors {
            LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        } else {
            appBackground.ignoresSafeArea()
        }
    }

    /// WhatsApp-style bubble colour palette for the "Chat bubble" picker.
    static let bubblePalette: [Color] = [
        Color(red: 0.30, green: 0.69, blue: 0.45), Color(red: 0.82, green: 0.95, blue: 0.82),
        Color(red: 0.36, green: 0.30, blue: 0.85), Color(red: 0.88, green: 0.85, blue: 0.98),
        Color(red: 0.66, green: 0.36, blue: 0.80), Color(red: 0.92, green: 0.85, blue: 0.95),
        Color(red: 0.83, green: 0.42, blue: 0.33), Color(red: 0.96, green: 0.86, blue: 0.82),
        Color(red: 0.22, green: 0.52, blue: 0.50), Color(red: 0.80, green: 0.93, blue: 0.90),
        Color(red: 0.23, green: 0.45, blue: 0.86), Color(red: 0.82, green: 0.89, blue: 0.97),
        Color(red: 0.13, green: 0.28, blue: 0.45), Color(red: 0.80, green: 0.86, blue: 0.91),
        Color(red: 0.22, green: 0.36, blue: 0.20), Color(red: 0.86, green: 0.90, blue: 0.84),
        Color(red: 0.42, green: 0.13, blue: 0.20), Color(red: 0.96, green: 0.82, blue: 0.86),
        Color(red: 0.16, green: 0.16, blue: 0.18), Color(red: 0.84, green: 0.86, blue: 0.88),
        Color(red: 0.30, green: 0.58, blue: 0.92), Color(red: 0.82, green: 0.89, blue: 0.97),
        Color(red: 0.55, green: 0.40, blue: 0.28), Color(red: 0.92, green: 0.84, blue: 0.78),
        Color(red: 0.69, green: 0.62, blue: 0.45), Color(red: 0.92, green: 0.90, blue: 0.83),
        Color(red: 0.27, green: 0.62, blue: 0.50), Color(red: 0.84, green: 0.96, blue: 0.90),
        Color(red: 0.85, green: 0.72, blue: 0.20), Color(red: 0.96, green: 0.95, blue: 0.70),
        Color(red: 0.45, green: 0.66, blue: 0.30), Color(red: 0.88, green: 0.96, blue: 0.78),
        Color(red: 0.83, green: 0.30, blue: 0.50), Color(red: 0.97, green: 0.85, blue: 0.90),
        Color.brandDanger, Color(red: 0.97, green: 0.84, blue: 0.84),
        Color(red: 0.84, green: 0.30, blue: 0.20), Color(red: 0.95, green: 0.85, blue: 0.80),
        Color(red: 0.82, green: 0.66, blue: 0.18), Color(red: 0.97, green: 0.93, blue: 0.78),
    ]
}

// MARK: - Conversation theme picker (WhatsApp-style)

struct ChatThemePicker: View {
    // scope == nil  -> global default (Chat Settings), writes prvio.chatTheme…
    // scope == id   -> per-conversation override, writes prvio.chatTheme.<id>…
    // Per-conversation keys default to the current global value so the picker
    // opens showing the conversation's effective theme.
    private let scope: String?
    @AppStorage private var selected: String
    @AppStorage private var bubbleHex: String
    @AppStorage private var bgID: String
    @AppStorage private var bgAnim: String
    @Environment(\.dismiss) private var dismiss

    init(scope: String? = nil) {
        self.scope = scope
        let suffix = scope.map { ".\($0)" } ?? ""
        let d = UserDefaults.standard
        let gTheme = scope == nil ? "appDefault" : (d.string(forKey: "prvio.chatTheme") ?? "appDefault")
        let gBubble = scope == nil ? "" : (d.string(forKey: "prvio.chatBubbleHex") ?? "")
        let gBg = scope == nil ? "" : (d.string(forKey: "prvio.chatBgID") ?? "")
        let gAnim = scope == nil ? "" : (d.string(forKey: "prvio.chatBgAnim") ?? "")
        _selected  = AppStorage(wrappedValue: gTheme,  "prvio.chatTheme\(suffix)")
        _bubbleHex = AppStorage(wrappedValue: gBubble, "prvio.chatBubbleHex\(suffix)")
        _bgID      = AppStorage(wrappedValue: gBg,     "prvio.chatBgID\(suffix)")
        _bgAnim    = AppStorage(wrappedValue: gAnim,   "prvio.chatBgAnim\(suffix)")
    }

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    private var bubbleColor: Color {
        (!bubbleHex.isEmpty ? Color(hex: bubbleHex) : nil) ?? ChatTheme.theme(for: selected).outgoingBubble
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Themes")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xl)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ChatTheme.all) { theme in
                                Button {
                                    selected = theme.id
                                    bubbleHex = ""; bgID = ""; bgAnim = ""   // theme overrides customizations
                                    HapticFeedback.impact(.light)
                                } label: {
                                    thumb(theme, isSelected: selected == theme.id && bubbleHex.isEmpty
                                                             && bgID.isEmpty && bgAnim.isEmpty)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(AppSpacing.md)
                        .liquidGlass(cornerRadius: 18)
                        .padding(.horizontal, AppSpacing.lg)

                        Text("Both the chat bubble and the conversation background will change.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xl).padding(.top, 2)

                        Text("Customize")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)

                        VStack(spacing: 0) {
                            NavigationLink {
                                BubbleColorPicker(scope: scope)
                            } label: {
                                customRow(icon: "bubble.left.fill", label: "Chat bubble") {
                                    Circle().fill(bubbleColor).frame(width: 22, height: 22)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                            NavigationLink {
                                BackgroundPicker(scope: scope)
                            } label: {
                                customRow(icon: "photo.fill", label: "Background") {
                                    backgroundSwatch
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .liquidGlass(cornerRadius: AppRadius.lg)
                        .padding(.horizontal, AppSpacing.lg)

                        Spacer(minLength: 20)
                    }
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Conversation theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        // Sheet-presented: a glass backdrop instead of the opaque app
        // background (the sub-pickers inherit the same NavigationStack).
        .presentationBackground(.thinMaterial)
    }

    @ViewBuilder private var backgroundSwatch: some View {
        if let preset = AnimatedBackgroundPreset.preset(for: bgAnim) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(preset.gradient)
                .frame(width: 30, height: 30)
        } else {
            let cols = ChatTheme.theme(for: bgID.isEmpty ? selected : bgID).backgroundColors
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cols.map { LinearGradient(colors: $0, startPoint: .top, endPoint: .bottom) }
                      ?? LinearGradient(colors: [Color.primary.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30)
        }
    }

    private func customRow<Trailing: View>(icon: String, label: String,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).frame(width: 26)
            Text(LocalizedStringKey(label)).font(.system(size: 16)).foregroundStyle(.primary)
            Spacer()
            trailing()
            Image(systemName: "chevron.right")
                .font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }

    // Phone-shaped preview: wallpaper + incoming/outgoing sample bubbles.
    private func thumb(_ theme: ChatTheme, isSelected: Bool) -> some View {
        ZStack {
            Group {
                if let cols = theme.backgroundColors {
                    LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
                } else {
                    appBackground
                }
            }
            VStack(spacing: 6) {
                Capsule().fill(Color.white.opacity(theme.isDark ? 0.85 : 0.95))
                    .frame(width: 38, height: 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule().fill(theme.outgoingBubble)
                    .frame(width: 42, height: 13)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(AppSpacing.sm)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white, theme.outgoingBubble)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(AppSpacing.xs)
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.12),
                              lineWidth: isSelected ? 2.5 : 1)
        )
    }
}

// MARK: - Chat bubble colour picker

struct BubbleColorPicker: View {
    @AppStorage private var bubbleHex: String
    @Environment(\.dismiss) private var dismiss

    init(scope: String? = nil) {
        let suffix = scope.map { ".\($0)" } ?? ""
        let g = scope == nil ? "" : (UserDefaults.standard.string(forKey: "prvio.chatBubbleHex") ?? "")
        _bubbleHex = AppStorage(wrappedValue: g, "prvio.chatBubbleHex\(suffix)")
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(ChatTheme.bubblePalette.enumerated()), id: \.offset) { _, color in
                    let hex = color.hexString()
                    Button {
                        bubbleHex = hex
                        HapticFeedback.impact(.light)
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 62, height: 62)
                            .overlay {
                                if bubbleHex == hex {
                                    Circle().strokeBorder(Color.primary, lineWidth: 3)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(color.isLight ? .black : .white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("Chat bubble")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Background (wallpaper) picker
//
// Restructured like the Messages background sheet: a live preview of the
// current choice up top, then Dynamic (animated mesh presets), Colors
// (static gradients) and Your Photo — each a titled section. Selection is
// exclusive across sections; the storage keys record which kind won.

struct BackgroundPicker: View {
    private let scope: String?
    @AppStorage private var bgID: String
    @AppStorage private var bgImage: String   // custom wallpaper file name ("" = none)
    @AppStorage private var bgAnim: String    // dynamic preset id ("" = none)
    @State private var photoItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    init(scope: String? = nil) {
        self.scope = scope
        let suffix = scope.map { ".\($0)" } ?? ""
        let d = UserDefaults.standard
        let gBg = scope == nil ? "" : (d.string(forKey: "prvio.chatBgID") ?? "")
        let gImg = scope == nil ? "" : (d.string(forKey: "prvio.chatBgImage") ?? "")
        let gAnim = scope == nil ? "" : (d.string(forKey: "prvio.chatBgAnim") ?? "")
        _bgID = AppStorage(wrappedValue: gBg, "prvio.chatBgID\(suffix)")
        _bgImage = AppStorage(wrappedValue: gImg, "prvio.chatBgImage\(suffix)")
        _bgAnim = AppStorage(wrappedValue: gAnim, "prvio.chatBgAnim\(suffix)")
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private var usingPhoto: Bool { !bgImage.isEmpty }
    private var usingDynamic: Bool { !usingPhoto && !bgAnim.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                livePreview
                dynamicSection
                colorsSection
                photoSection
                Spacer(minLength: 24)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
        }
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let name = ChatBackgroundStore.save(img, scope: scope) {
                    await MainActor.run {
                        bgImage = name; bgID = ""; bgAnim = ""
                        HapticFeedback.success()
                    }
                }
            }
        }
    }

    // MARK: Live preview — the actual background with sample bubbles on it.

    private var livePreview: some View {
        section(title: "Preview") {
            ZStack {
                ChatTheme.resolved(themeID: "appDefault", bubbleHex: "", bgID: bgID,
                                   bgImage: bgImage, bgAnim: bgAnim).background
                VStack(spacing: 8) {
                    HStack {
                        sampleBubble(fill: Color(.systemBackground).opacity(0.92), isOwn: false)
                        Spacer(minLength: 90)
                    }
                    HStack {
                        Spacer(minLength: 90)
                        sampleBubble(fill: Color.accentColor, isOwn: true)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
            )
        }
    }

    private func sampleBubble(fill: Color, isOwn: Bool) -> some View {
        Capsule()
            .fill(fill)
            .frame(width: isOwn ? 96 : 128, height: 30)
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    // MARK: Dynamic (animated) presets

    private var dynamicSection: some View {
        section(title: "Dynamic") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AnimatedBackgroundPreset.all) { preset in
                    Button {
                        bgAnim = preset.id; bgID = ""; bgImage = ""
                        HapticFeedback.impact(.light)
                    } label: {
                        tile(selected: usingDynamic && bgAnim == preset.id) {
                            ZStack(alignment: .bottom) {
                                AnimatedChatBackground(preset: preset)
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.28), in: Capsule())
                                    .padding(.bottom, AppSpacing.sm)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Static gradient presets

    private var colorsSection: some View {
        section(title: "Colors") {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ChatTheme.all) { theme in
                    let isSel = !usingPhoto && !usingDynamic && bgID == theme.id
                    Button {
                        bgID = theme.id; bgImage = ""; bgAnim = ""
                        HapticFeedback.impact(.light)
                    } label: {
                        tile(selected: isSel) {
                            Group {
                                if let cols = theme.backgroundColors {
                                    LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
                                } else {
                                    appBackground
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Your photo

    private var photoSection: some View {
        section(title: "Your photo") {
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        tile(selected: false) {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 24, weight: .semibold))
                                Text("Upload").font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.accentColor.opacity(0.1))
                        }
                    }
                    .buttonStyle(.plain)

                    if usingPhoto, let img = ChatBackgroundStore.image(named: bgImage) {
                        Button {
                            HapticFeedback.impact(.light)  // already selected — tap re-affirms
                        } label: {
                            tile(selected: true) {
                                // scaledToFill inside a clear overlay: the photo
                                // fills the tile without inflating its layout —
                                // a bare fill let portrait shots burst out of
                                // the grid and cover the Upload tile.
                                Color.clear
                                    .overlay(Image(uiImage: img).resizable().scaledToFill())
                                    .clipped()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if usingPhoto {
                    Button(role: .destructive) {
                        bgImage = ""; HapticFeedback.impact(.light)
                    } label: {
                        Label("Remove custom photo", systemImage: "trash")
                            .font(AppFont.subheadline)
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xxs)
            content()
        }
    }

    @ViewBuilder
    private func tile<Content: View>(selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white, Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(AppSpacing.xs)
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                              lineWidth: selected ? 2.5 : 1)
        )
    }
}
