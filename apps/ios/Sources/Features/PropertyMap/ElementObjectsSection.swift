import SwiftUI

// "Objects" attached to an element = inventory items linked to it.
// Realizes the Zone -> Element -> Object drill-down: on element X you see object Y.

struct ElementObjectsSection: View {
    let element: PropertyElement

    @StateObject private var inv = InventoryService()
    @State private var showLink = false

    private var linked: [InventoryItem] { inv.items.filter { $0.elementId == element.id } }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Objects", systemImage: "shippingbox.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showLink = true } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    }
                    .accessibilityLabel("Link object")
                }

                if linked.isEmpty {
                    Text("No objects linked yet").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(linked) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.categoryIcon)
                                .font(.system(size: 14)).foregroundStyle(item.categoryColor).frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.system(size: 14, weight: .medium))
                                if !item.brand.isEmpty {
                                    Text(item.brand).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button { Task { await unlink(item) } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.3))
                            }.buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .task { await inv.load(propertyId: element.propertyId) }
        .sheet(isPresented: $showLink) {
            LinkObjectsSheet(elementId: element.id, inv: inv)
        }
    }

    private func unlink(_ item: InventoryItem) async {
        var u = item; u.elementId = nil
        await inv.update(u)
        HapticFeedback.selection()
    }
}

// Pick inventory items to attach to this element.
private struct LinkObjectsSheet: View {
    let elementId: UUID
    @ObservedObject var inv: InventoryService
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [InventoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return inv.items }
        return inv.items.filter { $0.name.lowercased().contains(q) || $0.brand.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                if inv.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shippingbox").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("No inventory items").font(.headline)
                        Text("Add items in Inventory first, then link them here.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(40)
                } else {
                    List(filtered) { item in
                        Button { Task { await toggle(item) } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.categoryIcon).foregroundStyle(item.categoryColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                    if item.elementId != nil && item.elementId != elementId {
                                        Text("Linked elsewhere").font(.caption2).foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if item.elementId == elementId {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .searchable(text: $query, prompt: "Search inventory")
                }
            }
            .navigationTitle("Link objects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func toggle(_ item: InventoryItem) async {
        var u = item
        u.elementId = (item.elementId == elementId) ? nil : elementId
        await inv.update(u)
        HapticFeedback.selection()
    }
}
