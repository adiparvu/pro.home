import SwiftUI

// MARK: - Add Property Sheet
//
// Create flow on the shared PropertyFormContent (FormKit). Saving keeps
// today's pipeline — PropertyService.create — then honestly persists the
// extras through existing service calls only:
//   • year built  → PropertyService.update (create() has no year_built)
//   • cover photo → PropertyService.uploadPhoto
//   • purchase price / estimated value → PropertyValueService.add
//     (property_value_entries — the "Valoarea proprietății" history)

struct AddPropertySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PropertyService.self) private var propertyService
    // Optional on purpose: the sheet must keep working (minus the value
    // section) if a future presentation site lacks these services.
    @Environment(PropertyValueService.self) private var propertyValueService: PropertyValueService?
    @Environment(AppSettings.self) private var appSettings: AppSettings?

    @State private var draft = PropertyFormDraft()
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        FormScaffold(title: "prop_form_add_title",
                     saveLabel: "prop_form_add_action",
                     canSave: draft.canSave,
                     isSaving: isSaving,
                     error: $error,
                     onSave: { Task { await save() } }) {
            PropertyFormContent(draft: draft,
                                showsValueSection: propertyValueService != nil)
        }
        .onAppear {
            if let preferred = appSettings?.preferredCurrency, !preferred.isEmpty {
                draft.currency = preferred
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // A stale service error must not be mistaken for this save's outcome.
        propertyService.error = nil
        let existingIds = Set(propertyService.properties.map(\.id))

        await propertyService.create(
            name: draft.trimmedName,
            addressLine1: draft.trimmedAddress,
            city: draft.city.trimmingCharacters(in: .whitespacesAndNewlines),
            country: draft.country,
            propertyType: draft.propertyType,
            postalCode: draft.postalCode.isEmpty ? nil : draft.postalCode,
            sizeSqm: draft.area,
            numRooms: draft.rooms,
            latitude: draft.latitude,
            longitude: draft.longitude
        )

        if let message = propertyService.error {
            propertyService.error = nil
            error = message
            return
        }
        guard let created = propertyService.properties.first(where: { !existingIds.contains($0.id) }) else {
            // The row was created but the local list didn't surface it —
            // nothing more to attach, but the property itself exists.
            HapticFeedback.success()
            dismiss()
            return
        }

        // Year built rides an update because create() doesn't carry it.
        // Ordered before the photo upload: update() writes photo_url from the
        // model, so running it afterwards would clobber the fresh URL.
        if let year = draft.yearBuilt {
            var withYear = created
            withYear.yearBuilt = year
            await propertyService.update(withYear)
        }

        if let image = draft.coverImage {
            await propertyService.uploadPhoto(propertyId: created.id, image: image)
        }

        await saveValueEntries(propertyId: created.id)

        HapticFeedback.success()
        dismiss()
    }

    /// Seeds the property's value history: the purchase price (at its date)
    /// and today's owner estimate. Skipped entirely when both fields are
    /// blank — the section is optional and never writes placeholders.
    private func saveValueEntries(propertyId: UUID) async {
        guard let service = propertyValueService,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        let iso = ISO8601DateFormatter()

        if let price = draft.purchasePrice, price > 0 {
            await service.add(NewPropertyValuePayload(
                propertyId: propertyId,
                ownerId: ownerId,
                valueAmount: price,
                currency: draft.currency,
                source: String(localized: "prop_form_value_source_purchase"),
                notes: nil,
                enteredAt: iso.string(from: draft.purchaseDate)
            ))
        }
        if let estimate = draft.estimatedValue, estimate > 0 {
            await service.add(NewPropertyValuePayload(
                propertyId: propertyId,
                ownerId: ownerId,
                valueAmount: estimate,
                currency: draft.currency,
                source: String(localized: "prop_form_value_source_estimate"),
                notes: nil,
                enteredAt: iso.string(from: Date())
            ))
        }
    }
}
