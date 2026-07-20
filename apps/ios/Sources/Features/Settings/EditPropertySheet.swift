import SwiftUI

// MARK: - Edit Property Sheet
//
// The same PropertyFormContent as AddPropertySheet, plus the rich-profile
// history the edit flow has always owned (story, renovations, owners — all
// real columns). The Achiziție & valoare section is create-only by design:
// value entries are history rows, and re-saving an edit form must never
// duplicate them — the Valoarea proprietății page manages them afterwards.

struct EditPropertySheet: View {
    @Environment(\.dismiss) private var dismiss
    // Optional so the sheet renders even if a host forgets to inject the
    // service — only the cover upload needs it.
    @Environment(PropertyService.self) private var propertyService: PropertyService?

    let property: PropertyModel
    let onSave: (PropertyModel) async -> Void

    @State private var draft: PropertyFormDraft
    @State private var isSaving = false
    @State private var error: String?

    init(property: PropertyModel, onSave: @escaping (PropertyModel) async -> Void) {
        self.property = property
        self.onSave = onSave
        _draft = State(initialValue: PropertyFormDraft(property: property))
    }

    var body: some View {
        FormScaffold(title: "prop_form_edit_title",
                     saveLabel: "prop_form_save_action",
                     canSave: draft.canSave,
                     isSaving: isSaving,
                     error: $error,
                     onSave: { Task { await save() } }) {
            PropertyFormContent(draft: draft, showsValueSection: false)
            PropertyStoryEditor(draft: draft)
            PropertyRenovationsEditor(draft: draft)
            PropertyOwnersEditor(draft: draft)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        await onSave(draft.applied(to: property))

        // A freshly picked cover uploads after the row update — uploadPhoto
        // patches photo_url itself, so this order never loses either write.
        if let image = draft.coverImage {
            await propertyService?.uploadPhoto(propertyId: property.id, image: image)
        }

        HapticFeedback.success()
        dismiss()
    }
}
