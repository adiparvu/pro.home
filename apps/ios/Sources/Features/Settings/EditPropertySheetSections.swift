import SwiftUI

// MARK: - Edit-only history sections (story, renovations, owners)
//
// The property's rich profile — all existing columns (`story`,
// `renovations`, `owners`) — rebuilt on FormKit so the edit sheet speaks the
// same visual language as every other form in the app.

// MARK: Story

struct PropertyStoryEditor: View {
    @Bindable var draft: PropertyFormDraft

    var body: some View {
        FormGroup(title: "prop_form_story") {
            ZStack(alignment: .topLeading) {
                if draft.story.isEmpty {
                    Text("prop_form_story_placeholder")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.primary.opacity(0.28))
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, 13)
                }
                TextEditor(text: $draft.story)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
            }
        }
    }
}

// MARK: Renovations

struct PropertyRenovationsEditor: View {
    @Bindable var draft: PropertyFormDraft

    @State private var showForm = false
    @State private var newTitle = ""
    @State private var newFrom = ""
    @State private var newTo = ""

    private var canAdd: Bool { !newTitle.isEmpty && Int(newFrom) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorHeader(title: "prop_form_renovations", isExpanded: $showForm)

            if !draft.renovations.isEmpty {
                FormGroup {
                    ForEach(draft.renovations) { renovation in
                        historyRow(icon: "wrench.fill",
                                   tint: Color.accentColor,
                                   title: renovation.title,
                                   subtitle: renovation.yearRange) {
                            withAnimation(.snappy(duration: 0.2)) {
                                draft.renovations.removeAll { $0.id == renovation.id }
                            }
                        }
                        if renovation.id != draft.renovations.last?.id { FormDivider() }
                    }
                }
            }

            if showForm {
                VStack(spacing: 8) {
                    FormGroup {
                        FormRow(icon: "wrench.fill", tint: .accentColor) {
                            TextField("prop_form_renovation_title", text: $newTitle)
                                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                        }
                        FormDivider()
                        FormRow(icon: "calendar", tint: .accentColor) {
                            TextField("prop_form_year_from", text: $newFrom)
                                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                                .keyboardType(.numberPad)
                        }
                        FormDivider()
                        FormRow(icon: "calendar", tint: .accentColor) {
                            TextField("prop_form_year_to", text: $newTo)
                                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                                .keyboardType(.numberPad)
                        }
                    }
                    addButton(label: "prop_form_add_renovation", enabled: canAdd) {
                        guard let from = Int(newFrom) else { return }
                        withAnimation(.snappy(duration: 0.2)) {
                            draft.renovations.append(
                                Renovation(yearFrom: from, yearTo: Int(newTo), title: newTitle))
                            newTitle = ""; newFrom = ""; newTo = ""
                            showForm = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: Owners

struct PropertyOwnersEditor: View {
    @Bindable var draft: PropertyFormDraft

    @State private var showForm = false
    @State private var newName = ""
    @State private var newFrom = ""
    @State private var newTo = ""

    private var canAdd: Bool { !newName.isEmpty && Int(newFrom) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            editorHeader(title: "prop_form_owners", isExpanded: $showForm)

            if !draft.owners.isEmpty {
                FormGroup {
                    ForEach(draft.owners) { owner in
                        historyRow(icon: "person.fill",
                                   tint: Color.accentColor,
                                   title: owner.name,
                                   subtitle: owner.yearRange) {
                            withAnimation(.snappy(duration: 0.2)) {
                                draft.owners.removeAll { $0.id == owner.id }
                            }
                        }
                        if owner.id != draft.owners.last?.id { FormDivider() }
                    }
                }
            }

            if showForm {
                VStack(spacing: 8) {
                    FormGroup {
                        FormRow(icon: "person.fill", tint: .accentColor) {
                            TextField("prop_form_owner_name", text: $newName)
                                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                                .textInputAutocapitalization(.words)
                        }
                        FormDivider()
                        FormRow(icon: "calendar", tint: .accentColor) {
                            TextField("prop_form_year_from", text: $newFrom)
                                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                                .keyboardType(.numberPad)
                        }
                        FormDivider()
                        FormRow(icon: "calendar", tint: .accentColor) {
                            TextField("prop_form_year_to", text: $newTo)
                                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                                .keyboardType(.numberPad)
                        }
                    }
                    addButton(label: "prop_form_add_owner", enabled: canAdd) {
                        guard let from = Int(newFrom) else { return }
                        withAnimation(.snappy(duration: 0.2)) {
                            draft.owners.append(
                                OwnerRecord(name: newName, yearFrom: from, yearTo: Int(newTo)))
                            newName = ""; newFrom = ""; newTo = ""
                            showForm = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: Shared pieces

/// Section label + the +/− toggle that reveals the inline add form.
private func editorHeader(title: LocalizedStringKey, isExpanded: Binding<Bool>) -> some View {
    // Bound to LocalizedStringKey first — a ternary of string literals is a
    // `String` and would skip the catalog.
    let toggleKey: LocalizedStringKey = isExpanded.wrappedValue
        ? "prop_form_hide_form" : "prop_form_add_action"
    return HStack {
        Text(title)
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        Spacer()
        Button {
            HapticFeedback.impact(.light)
            withAnimation(.snappy(duration: 0.25)) { isExpanded.wrappedValue.toggle() }
        } label: {
            Image(systemName: isExpanded.wrappedValue ? "minus.circle.fill" : "plus.circle.fill")
                .font(AppFont.scaled(18))
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(toggleKey))
    }
    .padding(.leading, AppSpacing.xxs)
}

/// One list entry with an inline delete — renovations and owners share it.
private func historyRow(icon: String, tint: Color, title: String, subtitle: String,
                        onDelete: @escaping () -> Void) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(AppFont.scaled(13))
            .foregroundStyle(tint)
            .frame(width: 22)
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title).font(AppFont.footnote).foregroundStyle(.primary)
            Text(verbatim: subtitle).font(AppFont.scaled(12)).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(AppFont.scaled(16))
                .foregroundStyle(Color.primary.opacity(0.3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("prop_form_delete"))
    }
    .padding(.horizontal, AppSpacing.lg)
    .padding(.vertical, 10)
}

/// The confirm button under an inline add form.
private func addButton(label: LocalizedStringKey, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
    Button {
        HapticFeedback.impact(.light)
        action()
    } label: {
        Text(label)
            .font(AppFont.subheadline)
            .foregroundStyle(enabled ? Color.accentColor : Color.primary.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
}
