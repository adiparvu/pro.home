import SwiftUI
import Foundation
import FoundationModels

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
        if q.contains("task") || q.contains("overdue") || q.contains("todo") {
            let overdue = tasks.filter { $0.isOverdue }.count
            let open = tasks.filter { !$0.isCompleted }.count
            if overdue > 0 { return "You have \(overdue) overdue task\(overdue == 1 ? "" : "s") and \(open) open in total. The most urgent: \(tasks.filter { $0.isOverdue }.first?.title ?? "—")." }
            return "You have \(open) open task\(open == 1 ? "" : "s"), none overdue. Great job staying on top of things!"
        }
        // Finance
        if q.contains("financ") || q.contains("income") || q.contains("expense") || q.contains("money") || q.contains("spend") {
            let net = monthlyIncome - monthlyExpenses
            return "This month: \(incomeSymbol)\(Int(monthlyIncome)) income, \(incomeSymbol)\(Int(monthlyExpenses)) expenses, net \(net >= 0 ? "+" : "")\(incomeSymbol)\(Int(net))."
        }
        // Documents
        if q.contains("document") || q.contains("expir") || q.contains("warranty") || q.contains("insurance") {
            let expiring = documents.filter { $0.isExpiringSoon }.count
            if expiring > 0 { return "You have \(expiring) document\(expiring == 1 ? "" : "s") expiring within 30 days. Check the Documents section to renew them." }
            return "All your documents are up to date. No renewals needed soon."
        }
        // Property
        if q.contains("property") || q.contains("house") || q.contains("home") || q.contains("hello") || q.contains("hi") || q.contains("hey") {
            return "I'm your property assistant for \(propertyName.isEmpty ? "your property" : propertyName). Ask me about tasks, finances, or documents!"
        }
        // Health
        if q.contains("health") || q.contains("score") || q.contains("status") {
            let overdue = tasks.filter { $0.isOverdue }.count
            let score = max(min(100 - overdue * 12, 100), 0)
            return "Your property health score is around \(score)/100. \(score >= 80 ? "Everything looks great!" : "Consider addressing the overdue tasks to improve it.")"
        }
        // Help
        if q.contains("help") || q.contains("what can") {
            return "I can help with:\n• Task status & reminders\n• Financial summaries\n• Document expiry alerts\n• Property health overview\n\nJust ask naturally!"
        }
        // Default
        return "I'm your local property assistant. I can answer questions about your tasks, finances, and documents. What would you like to know?"
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
                        .font(.system(size: 13, weight: .semibold))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 20)
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
                .tint(.blue)
                .focused($focused)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(input.isEmpty ? .primary.opacity(0.2) : .blue)
            }
            .disabled(input.isEmpty || isThinking)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(.blue)
                        : AnyShapeStyle(.primary.opacity(0.08)),
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
                        .fill(.primary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == Double(i) ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 60)
        }
        .onAppear { phase = 2 }
    }
}
