import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var financialService: FinancialService
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool
    @StateObject private var speech = SpeechRecognizer()

    private var results: SearchResults {
        guard query.count >= 2 else { return .empty }
        let q = query.lowercased()
        return SearchResults(
            tasks: taskService.tasks.filter {
                $0.title.lowercased().contains(q) ||
                $0.category.lowercased().contains(q) ||
                ($0.description?.lowercased().contains(q) ?? false)
            },
            documents: documentService.documents.filter {
                $0.name.lowercased().contains(q) ||
                $0.category.lowercased().contains(q)
            },
            finances: financialService.records.filter {
                $0.title.lowercased().contains(q) ||
                $0.category.lowercased().contains(q)
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    if query.count < 2 {
                        recentHints
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        resultsList
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
            }
            .onAppear { focused = true }
            .onDisappear { speech.stop() }
            .onChange(of: speech.transcript) { _, newValue in
                if !newValue.isEmpty { query = newValue }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(speech.isListening ? Color.red : Color.primary.opacity(0.4))

            TextField("Tasks, documents, finances…", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.blue)
                .focused($focused)
                .submitLabel(.search)

            if speech.isListening {
                Button { speech.stop() } label: {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                }
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
            } else {
                Button {
                    focused = false
                    Task { await speech.startListening() }
                } label: {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            speech.isListening
                ? .red.opacity(0.08)
                : Color.primary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(speech.isListening ? .red.opacity(0.3) : .clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: speech.isListening)
    }

    // MARK: - Hints

    private var recentHints: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.primary.opacity(0.12))
            VStack(spacing: 8) {
                Text("Search across tasks, documents, and finances")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                HStack(spacing: 6) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.2))
                    Text("Tap the microphone to search by voice")
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.2))
                }
            }
            Spacer()
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("No results for \"\(query)\"")
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.35))
            Spacer()
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                if !results.tasks.isEmpty {
                    SearchSection(title: "Tasks", icon: "checklist", count: results.tasks.count) {
                        ForEach(results.tasks) { task in
                            SearchRow(
                                icon: "checklist",
                                color: task.priorityColor,
                                title: task.title,
                                subtitle: "\(task.category.capitalized) · \(task.dueDateDisplay)",
                                badge: task.isOverdue ? "Overdue" : nil,
                                badgeColor: .red
                            )
                        }
                    }
                }
                if !results.documents.isEmpty {
                    SearchSection(title: "Documents", icon: "doc.text.fill", count: results.documents.count) {
                        ForEach(results.documents) { doc in
                            SearchRow(
                                icon: doc.categoryIcon,
                                color: .orange,
                                title: doc.name,
                                subtitle: doc.category.capitalized,
                                badge: doc.isExpiringSoon ? "Expiring" : nil,
                                badgeColor: .orange
                            )
                        }
                    }
                }
                if !results.finances.isEmpty {
                    SearchSection(title: "Finances", icon: "banknote.fill", count: results.finances.count) {
                        ForEach(results.finances) { record in
                            SearchRow(
                                icon: record.isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                                color: record.isIncome ? Color(red: 0.3, green: 0.85, blue: 0.5) : Color.red,
                                title: record.title,
                                subtitle: "\(record.category.capitalized) · \(record.dateFormatted)",
                                badge: record.amountDisplay,
                                badgeColor: Color.primary.opacity(0.4)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Models

private struct SearchResults {
    let tasks: [MaintenanceTask]
    let documents: [DocumentModel]
    let finances: [FinancialRecord]

    var isEmpty: Bool { tasks.isEmpty && documents.isEmpty && finances.isEmpty }
    static let empty = SearchResults(tasks: [], documents: [], finances: [])
}

// MARK: - Components

private struct SearchSection<Content: View>: View {
    let title: String
    let icon: String
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.35))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.35))
                Text("(\(count))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.2))
            }
            .padding(.leading, 4)

            VStack(spacing: 6) { content }
        }
    }
}

private struct SearchRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var badge: String?
    var badgeColor: Color = .blue

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            if let badge = badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}
