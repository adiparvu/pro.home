import SwiftUI

// Free-form tags on an element (add/remove). Edits persist via elementService.

struct ElementTagsSection: View {
    let elementId: UUID

    @Environment(PropertyElementService.self) private var elementService
    @State private var newTag = ""

    private var element: PropertyElement? { elementService.elements.first { $0.id == elementId } }

    var body: some View {
        if let el = element {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Tags", systemImage: "tag")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                    if !el.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(el.tags, id: \.self) { tag in
                                    HStack(spacing: 5) {
                                        Text(tag).font(AppFont.scaled(13, weight: .medium))
                                        Button { remove(tag, el) } label: {
                                            Image(systemName: "xmark.circle.fill").font(AppFont.scaled(12))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Remove tag \(tag)")
                                    }
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 10).padding(.vertical, AppSpacing.xs)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Add tag", text: $newTag)
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 10))
                            .onSubmit { add(el) }
                        Button { add(el) } label: {
                            Image(systemName: "plus.circle.fill").font(AppFont.scaled(22)).foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add tag")
                    }
                }
            }
        }
    }

    private func add(_ el: PropertyElement) {
        let t = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty, !el.tags.contains(t) else { newTag = ""; return }
        var u = el; u.tags.append(t); newTag = ""
        Task { await elementService.update(u) }
        HapticFeedback.selection()
    }

    private func remove(_ tag: String, _ el: PropertyElement) {
        var u = el; u.tags.removeAll { $0 == tag }
        Task { await elementService.update(u) }
    }
}
