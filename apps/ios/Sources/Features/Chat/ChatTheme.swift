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
    ]

    static func theme(for id: String) -> ChatTheme { all.first { $0.id == id } ?? all[0] }

    @ViewBuilder var background: some View {
        if let cols = backgroundColors {
            LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        } else {
            appBackground.ignoresSafeArea()
        }
    }
}

// MARK: - Theme picker

struct ChatThemePicker: View {
    @AppStorage("prvio.chatTheme") private var selected = "appDefault"
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ChatTheme.all) { theme in
                            Button {
                                selected = theme.id
                                HapticFeedback.impact(.light)
                            } label: {
                                thumb(theme, isSelected: selected == theme.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)

                    Text("Both the chat bubble and the conversation background will change.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 20)
                }
            }
            .navigationTitle("Conversation theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func thumb(_ theme: ChatTheme, isSelected: Bool) -> some View {
        ZStack {
            Group {
                if let cols = theme.backgroundColors {
                    LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
                } else {
                    appBackground
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Capsule()
                    .fill(Color.primary.opacity(theme.isDark ? 0.25 : 0.12))
                    .frame(width: 52, height: 16)
                Capsule()
                    .fill(theme.outgoingBubble)
                    .frame(width: 60, height: 16)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white, theme.outgoingBubble)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? theme.outgoingBubble : Color.primary.opacity(0.12),
                              lineWidth: isSelected ? 2.5 : 1)
        )
    }
}
