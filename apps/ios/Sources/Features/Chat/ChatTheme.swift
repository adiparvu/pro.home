import SwiftUI

// MARK: - Chat theme (conversation background + bubble color)

struct ChatTheme: Identifiable {
    let id: String
    let name: String
    let outgoingBubble: Color
    let backgroundColors: [Color]?   // nil = app default background
    let isDark: Bool

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
    /// per-user customizations (custom bubble colour, custom background).
    static func resolved(themeID: String, bubbleHex: String, bgID: String) -> ChatTheme {
        let base = theme(for: themeID)
        let bubble: Color = (!bubbleHex.isEmpty ? Color(hex: bubbleHex) : nil) ?? base.outgoingBubble
        let bgTheme = bgID.isEmpty ? base : theme(for: bgID)
        let isPlainDefault = themeID == "appDefault" && bubbleHex.isEmpty && bgID.isEmpty
        return ChatTheme(
            id: isPlainDefault ? "appDefault" : "custom",
            name: base.name,
            outgoingBubble: bubble,
            backgroundColors: bgTheme.backgroundColors,
            isDark: bgTheme.isDark
        )
    }

    @ViewBuilder var background: some View {
        if let cols = backgroundColors {
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
        Color(red: 0.85, green: 0.20, blue: 0.20), Color(red: 0.97, green: 0.84, blue: 0.84),
        Color(red: 0.84, green: 0.30, blue: 0.20), Color(red: 0.95, green: 0.85, blue: 0.80),
        Color(red: 0.82, green: 0.66, blue: 0.18), Color(red: 0.97, green: 0.93, blue: 0.78),
    ]
}

// MARK: - Conversation theme picker (WhatsApp-style)

struct ChatThemePicker: View {
    @AppStorage("prvio.chatTheme") private var selected = "appDefault"
    @AppStorage("prvio.chatBubbleHex") private var bubbleHex = ""
    @AppStorage("prvio.chatBgID") private var bgID = ""
    @Environment(\.dismiss) private var dismiss

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
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Themes")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, 20)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ChatTheme.all) { theme in
                                Button {
                                    selected = theme.id
                                    bubbleHex = ""; bgID = ""   // theme overrides customizations
                                    HapticFeedback.impact(.light)
                                } label: {
                                    thumb(theme, isSelected: selected == theme.id && bubbleHex.isEmpty && bgID.isEmpty)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .liquidGlass(cornerRadius: 18)
                        .padding(.horizontal, 16)

                        Text("Both the chat bubble and the conversation background will change.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, 20).padding(.top, 2)

                        Text("Customize")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, 20).padding(.top, 8)

                        VStack(spacing: 0) {
                            NavigationLink {
                                BubbleColorPicker()
                            } label: {
                                customRow(icon: "bubble.left.fill", label: "Chat bubble") {
                                    Circle().fill(bubbleColor).frame(width: 22, height: 22)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                            NavigationLink {
                                BackgroundPicker()
                            } label: {
                                customRow(icon: "photo.fill", label: "Background") {
                                    backgroundSwatch
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .liquidGlass(cornerRadius: 16)
                        .padding(.horizontal, 16)

                        Spacer(minLength: 20)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Conversation theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder private var backgroundSwatch: some View {
        let cols = ChatTheme.theme(for: bgID.isEmpty ? selected : bgID).backgroundColors
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(cols.map { LinearGradient(colors: $0, startPoint: .top, endPoint: .bottom) }
                  ?? LinearGradient(colors: [Color.primary.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            .frame(width: 30, height: 30)
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
        .padding(.horizontal, 16).padding(.vertical, 12)
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
            .padding(8)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white, theme.outgoingBubble)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
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
    @AppStorage("prvio.chatBubbleHex") private var bubbleHex = ""
    @Environment(\.dismiss) private var dismiss

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
            .padding(20)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Chat bubble")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Background (wallpaper) picker

struct BackgroundPicker: View {
    @AppStorage("prvio.chatBgID") private var bgID = ""
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ChatTheme.all) { theme in
                    Button {
                        bgID = theme.id
                        HapticFeedback.impact(.light)
                    } label: {
                        ZStack {
                            Group {
                                if let cols = theme.backgroundColors {
                                    LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
                                } else {
                                    appBackground
                                }
                            }
                            if bgID == theme.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(.white, Color.accentColor)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                    .padding(6)
                            }
                        }
                        .aspectRatio(0.62, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(bgID == theme.id ? Color.accentColor : Color.primary.opacity(0.12),
                                              lineWidth: bgID == theme.id ? 2.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
    }
}
