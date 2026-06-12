import SwiftUI

struct ARIAView: View {
    @State private var messages: [ARIAMessage] = ARIAMessage.welcome
    @State private var input = ""
    @State private var isThinking = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARIA")
                            .font(.title2.weight(.bold))
                        Text("AI Property Assistant")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation { messages = ARIAMessage.welcome }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if isThinking {
                                ThinkingBubble()
                                    .id("thinking")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.bottom, 20)
                    }
                    .onChange(of: messages.count) {
                        withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: isThinking) {
                        if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                    }
                }

                // Input
                HStack(spacing: 10) {
                    TextField("Ask about your property...", text: $input, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                        )

                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 40, height: 40)
                            .background(.white, in: Circle())
                    }
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                    .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
                }
            }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(ARIAMessage(role: .user, content: text))
        isThinking = true

        // Simulate AI response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isThinking = false
            messages.append(ARIAMessage(role: .aria, content: ariaResponse(for: text)))
        }
    }

    private func ariaResponse(for query: String) -> String {
        let q = query.lowercased()
        if q.contains("health") || q.contains("score") {
            return "Your property health score is **78/100** — rated Good. The main factors dragging it down are 2 overdue maintenance tasks and 1 safety recall. Completing those would push you to ~87."
        } else if q.contains("task") {
            return "You have **7 open tasks**: 2 are overdue (replace kitchen faucet, check gutters). I'd prioritize the kitchen faucet — it's been overdue the longest and could cause water damage."
        } else if q.contains("yield") || q.contains("income") {
            return "Your gross rental yield is **6.8%** and net yield is **4.2%**. That's above the national average of 5.1% gross. Your net income this month is €2,310 after expenses."
        } else if q.contains("forecast") {
            return "Based on current trends, I forecast **€39,600** in rental income over the next 12 months — that's +8.3% vs last year. Key risks: lease renewal in July and insurance renewal in August."
        } else {
            return "I can help you with your property health, maintenance tasks, finances, occupancy, and forecasts. What would you like to know?"
        }
    }
}

private struct MessageBubble: View {
    let message: ARIAMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            if !isUser {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            Text(LocalizedStringKey(message.content))
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? AnyShapeStyle(.white.opacity(0.12)) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(isUser ? 0 : 0.08), lineWidth: 0.5)
                )

            if !isUser { Spacer(minLength: 48) }
        }
    }
}

private struct ThinkingBubble: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .scaleEffect(phase == i ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 48)
        }
        .onAppear { phase = 1 }
    }
}

// MARK: - Model

struct ARIAMessage: Identifiable {
    let id = UUID()
    enum Role { case user, aria }
    let role: Role
    let content: String

    static let welcome = [
        ARIAMessage(role: .aria, content: "Hi! I'm ARIA, your AI property assistant. I can help you with health scores, maintenance tasks, finances, and forecasts. What would you like to know?")
    ]
}
