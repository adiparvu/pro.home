import SwiftUI

// Searchable grid of every PropertyElementType — keeps the Add form tidy while
// still giving access to the full icon set.

struct ElementTypePickerSheet: View {
    let selected: PropertyElementType
    let onSelect: (PropertyElementType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [PropertyElementType] {
        let all = PropertyElementType.allCases
        guard !query.isEmpty else { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    private let cols = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    if !query.isEmpty && filtered.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
                    } else {
                        typeGrid
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search type")
            .navigationTitle("Element type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }

    private var typeGrid: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(filtered, id: \.self) { type in
                Button {
                    onSelect(type)
                    HapticFeedback.selection()
                    dismiss()
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(type.accentColor.opacity(selected == type ? 0.95 : 0.16))
                                .frame(width: 50, height: 50)
                            Image(systemName: type.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(selected == type ? .white : type.accentColor)
                        }
                        Text(LocalizedStringKey(type.displayName))
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(height: 28)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(selected == type ? 0.10 : 0.04))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.lg)
    }
}
