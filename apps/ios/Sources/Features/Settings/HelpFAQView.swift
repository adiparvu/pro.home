import SwiftUI

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
    var isExpanded = false
}

struct HelpFAQView: View {
    @State private var items: [FAQItem] = [
        FAQItem(question: "How do I add a property?", answer: "Go to Settings → My Property → tap the + button. Fill in the address, type, and optional photo. You can manage multiple properties from the same account."),
        FAQItem(question: "How does the Health Score work?", answer: "The Health Score (0–100) is calculated from overdue tasks, expiring documents, and maintenance frequency. Complete tasks and renew documents to improve it."),
        FAQItem(question: "Can I invite family members?", answer: "Yes. Go to Settings → Family Members → tap the invite icon. Enter their email — they'll receive a link to join your property."),
        FAQItem(question: "How do I set up recurring tasks?", answer: "When creating a task, toggle 'Recurring' and choose a frequency (daily, weekly, monthly, yearly). The task will auto-recreate after completion."),
        FAQItem(question: "Is my data backed up?", answer: "Yes — all data is stored in Supabase (PostgreSQL) with automatic daily backups. Your data is safe even if you change devices."),
        FAQItem(question: "How does ARIA work?", answer: "ARIA is your AI property assistant powered by Claude. It has context about your tasks, finances, and documents, so you can ask it anything about your home."),
        FAQItem(question: "Can I export my data?", answer: "Yes. Go to your Profile → Security & Privacy → Export My Data. You'll get a JSON file with all your tasks, finances, documents, and more."),
        FAQItem(question: "How do I contact support?", answer: "Email us at support@prvio.app. We typically respond within 24 hours on business days."),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(items.indices, id: \.self) { i in
                    FAQRow(item: $items[i])
                }

                VStack(spacing: 12) {
                    Text("Still need help?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Button {
                        if let url = URL(string: "mailto:support@prvio.app") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Email Support", systemImage: "envelope.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Ajutor & FAQ")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct FAQRow: View {
    @Binding var item: FAQItem

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    item.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(item.question)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: item.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if item.isExpanded {
                Text(item.answer)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
