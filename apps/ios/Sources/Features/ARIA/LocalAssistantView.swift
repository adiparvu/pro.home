import SwiftUI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Message model (keep same as before for history)
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
    let timestamp = Date()
    enum ChatRole { case user, assistant }
}

// MARK: - Rule-based fallback engine
struct PropertyBotEngine {
    let tasks: [MaintenanceTask]
    let finances: [FinancialRecord]   // pass currentMonthRecords
    let documents: [DocumentModel]
    let propertyName: String
    let incomeSymbol: String
    let monthlyIncome: Double
    let monthlyExpenses: Double

    func respond(to input: String) -> String {
        let q = input.lowercased()
        // Tasks
        if q.contains("task") || q.contains("overdue") || q.contains("todo")
            || q.contains("sarcin") || q.contains("depășit") || q.contains("întârziat") {
            let overdue = tasks.filter { $0.isOverdue }.count
            let open = tasks.filter { !$0.isCompleted }.count
            if overdue > 0 {
                let urgent = tasks.filter { $0.isOverdue }.first?.title ?? "—"
                return String(format: String(localized: "You have %d overdue tasks and %d open. Most urgent: %@"), overdue, open, urgent)
            }
            return String(format: String(localized: "You have %d open tasks, none overdue. Great job!"), open)
        }
        // Finance
        if q.contains("financ") || q.contains("income") || q.contains("expense") || q.contains("money")
            || q.contains("cheltuial") || q.contains("venit") || q.contains("bani") {
            let net = monthlyIncome - monthlyExpenses
            let sign = net >= 0 ? "+" : ""
            return String(format: String(localized: "This month: %@%d income, %@%d expenses, net %@%@%d."),
                          incomeSymbol, Int(monthlyIncome), incomeSymbol, Int(monthlyExpenses),
                          sign, incomeSymbol, Int(abs(net)))
        }
        // Documents
        if q.contains("document") || q.contains("expir") || q.contains("warranty") || q.contains("insurance")
            || q.contains("garanți") || q.contains("asigurare") {
            let expiring = documents.filter { $0.isExpiringSoon }.count
            if expiring > 0 {
                return String(format: String(localized: "You have %d documents expiring within 30 days."), expiring)
            }
            return String(localized: "All your documents are up to date.")
        }
        // Property
        if q.contains("property") || q.contains("house") || q.contains("home") || q.contains("hello")
            || q.contains("bună") || q.contains("salut") || q.contains("proprietate") || q.contains("casă") {
            let name = propertyName.isEmpty ? String(localized: "your property") : propertyName
            return String(format: String(localized: "I'm your property assistant for %@. Ask about tasks, finances or documents!"), name)
        }
        // Health
        if q.contains("health") || q.contains("score") || q.contains("status")
            || q.contains("sănătate") || q.contains("scor") || q.contains("stare") {
            let overdue = tasks.filter { $0.isOverdue }.count
            let score = max(min(100 - overdue * 12, 100), 0)
            let comment = score >= 80
                ? String(localized: "Everything looks great!")
                : String(localized: "Consider addressing the overdue tasks to improve it.")
            return String(format: String(localized: "Your property health score is around %d/100. %@"), score, comment)
        }
        // Help
        if q.contains("help") || q.contains("what can") || q.contains("ajutor") || q.contains("ce poți") {
            return String(localized: "I can help with tasks, finances, documents and property health. Just ask naturally!")
        }
        // Default
        return String(localized: "I'm your local property assistant. Ask me about tasks, finances or documents.")
    }
}

struct LocalAssistantView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var propertyService: PropertyService

    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var isThinking = false
    @FocusState private var focused: Bool

    private var engine: PropertyBotEngine {
        PropertyBotEngine(
            tasks: taskService.tasks,
            finances: financialService.currentMonthRecords,
            documents: documentService.documents,
            propertyName: propertyService.primary?.name ?? "",
            incomeSymbol: financialService.currencySymbol,
            monthlyIncome: financialService.currentMonthIncome,
            monthlyExpenses: financialService.currentMonthExpenses
        )
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                messageList
                inputBar
            }
        }
        .onAppear {
            if messages.isEmpty {
                messages = [ChatMessage(role: .assistant, text: "Hi! I'm your local property assistant — running entirely on your device, no internet needed.\n\nAsk me about your tasks, finances, or documents!")]
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Assistant")
                        .font(.title2.weight(.bold))
                    Image(systemName: "cpu.fill")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.9))
                }
                if #available(iOS 26.0, *) {
                    Text("Apple Intelligence · On-device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Local · No internet required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                withAnimation { messages = [messages[0]] }
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(AppFont.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .glassCircle()
            .accessibilityLabel("Reset conversation")
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.base)
    }

    // MARK: - Message list
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { msg in
                        LocalMessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if isThinking {
                        ThinkingBubble()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .padding(.bottom, AppSpacing.xl)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isThinking) { _, _ in
                if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Input bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your property…", text: $input, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .focused($focused)
                .lineLimit(1...4)
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))

            Button {
                guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(input.isEmpty ? Color.primary.opacity(0.2) : Color.accentColor)
            }
            .disabled(input.isEmpty || isThinking)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    // MARK: - Send
    private func send() {
        let text = input.trimmingCharacters(in: .whitespaces)
        input = ""
        HapticFeedback.impact(.light)
        messages.append(ChatMessage(role: .user, text: text))
        isThinking = true

        Task {
            let reply: String
            if #available(iOS 26.0, *) {
                reply = await respondWithFoundationModels(text)
            } else {
                // Small delay for natural feel
                try? await Task.sleep(for: .milliseconds(600))
                reply = engine.respond(to: text)
            }
            await MainActor.run {
                isThinking = false
                messages.append(ChatMessage(role: .assistant, text: reply))
                HapticFeedback.impact(.light)
            }
        }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func respondWithFoundationModels(_ text: String) async -> String {
        let property = propertyService.primary?.name ?? "your property"
        let overdue = taskService.overdueCount
        let open = taskService.openCount
        let income = financialService.currentMonthIncome
        let expenses = financialService.currentMonthExpenses
        let sym = financialService.currencySymbol
        let expiringDocs = documentService.expiringDocs.count

        let systemPrompt = """
        You are a helpful property management assistant for \(property).
        Current data:
        - Open tasks: \(open), Overdue: \(overdue)
        - Monthly income: \(sym)\(Int(income)), Expenses: \(sym)\(Int(expenses))
        - Documents expiring soon: \(expiringDocs)
        Answer concisely. You run entirely on-device.
        """

        do {
            let session = LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: text)
            return response.content
        } catch {
            return engine.respond(to: text)
        }
    }
    #else
    @available(iOS 26.0, *)
    private func respondWithFoundationModels(_ text: String) async -> String {
        try? await Task.sleep(for: .milliseconds(600))
        return engine.respond(to: text)
    }
    #endif
}

// MARK: - Bubbles
private struct LocalMessageBubble: View {
    let message: ChatMessage
    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }
            if !isUser {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                }
            }
            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(.blue)
                        : AnyShapeStyle(Color.primary.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if !isUser { Spacer(minLength: 60) }
        }
    }
}

private struct ThinkingBubble: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: "cpu.fill").font(.system(size: 12)).foregroundStyle(.primary)
            }
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.primary.opacity(AppOpacity.mediumText))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == Double(i) ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 60)
        }
        .onAppear { phase = 2 }
    }
}
