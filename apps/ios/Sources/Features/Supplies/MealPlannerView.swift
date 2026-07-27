import SwiftUI

// MARK: - Meal planner — week page + meal form
//
// "Planificator de mese": the week as seven day cards, each with the four
// slots of a family table. Ingredients push into the shopping lists (only
// what's missing), and a cooked meal consumes matching pantry stock. Reached
// from the Supplies page — the planner lives where the food already lives.

/// Identity for the "add into this day+slot" sheet.
private struct MealAddTarget: Identifiable {
    let day: Date
    let slot: MealSlot
    var id: String { "\(day.timeIntervalSince1970):\(slot.rawValue)" }
}

struct MealPlannerView: View {
    @Environment(MealPlanService.self) private var service
    @Environment(SupplyService.self) private var supplyService
    @Environment(PantryService.self) private var pantryService
    @Environment(PropertyService.self) private var propertyService

    @State private var weekStart: Date = MealPlannerView.startOfWeek(Date())
    @State private var addTarget: MealAddTarget?
    @State private var editingMeal: MealPlan?
    @State private var sendMeal: MealPlan?

    private var cal: Calendar { Calendar.current }
    private var weekDays: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                weekSelector
                ForEach(weekDays, id: \.self) { day in
                    daySection(day)
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("meal_planner_title")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $addTarget) { target in
            MealFormSheet(day: target.day, slot: target.slot)
        }
        .sheet(item: $editingMeal) { meal in
            MealFormSheet(day: meal.date ?? Date(), slot: meal.slot, editing: meal)
        }
        .confirmationDialog("meal_pick_list_title", isPresented: Binding(
            get: { sendMeal != nil && supplyService.lists.count > 1 },
            set: { if !$0 { sendMeal = nil } }
        ), titleVisibility: .visible) {
            if let meal = sendMeal {
                ForEach(supplyService.lists) { list in
                    Button(list.name) {
                        Task { await send(meal, to: list.id) }
                    }
                }
            }
        }
        .task {
            await service.loadIfNeeded()
            if supplyService.lists.isEmpty, let id = propertyService.primary?.id {
                await supplyService.load(propertyId: id)
            }
            if pantryService.items.isEmpty, let id = propertyService.primary?.id {
                await pantryService.load(propertyId: id)
            }
        }
        .refreshable { await service.load() }
    }

    // MARK: Week navigation

    private var weekSelector: some View {
        HStack(spacing: AppSpacing.md) {
            Button { shiftWeek(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .liquidGlass(cornerRadius: AppRadius.xl)
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 1) {
                Text(verbatim: weekLabel)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                if !cal.isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear) {
                    Button {
                        withAnimation(.snappy) { weekStart = Self.startOfWeek(Date()) }
                    } label: {
                        Text("meal_back_to_today")
                            .font(AppFont.scaled(12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Button { shiftWeek(1) } label: {
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .liquidGlass(cornerRadius: AppRadius.xl)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekLabel: String {
        guard let end = cal.date(byAdding: .day, value: 6, to: weekStart) else { return "" }
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(weekStart.formatted(fmt)) – \(end.formatted(fmt))"
    }

    private func shiftWeek(_ delta: Int) {
        guard let next = cal.date(byAdding: .weekOfYear, value: delta, to: weekStart) else { return }
        withAnimation(.snappy) { weekStart = next }
        HapticFeedback.selection()
    }

    static func startOfWeek(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start
            ?? Calendar.current.startOfDay(for: date)
    }

    // MARK: Day section

    private func daySection(_ day: Date) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(verbatim: dayLabel(day))
                .font(AppFont.scaled(16, weight: .bold))
                .foregroundStyle(cal.isDateInToday(day) ? Color.accentColor : .primary)
            VStack(spacing: 0) {
                ForEach(MealSlot.allCases) { slot in
                    slotRow(day: day, slot: slot)
                    if slot != MealSlot.allCases.last {
                        FormDivider()
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let label = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    @ViewBuilder
    private func slotRow(day: Date, slot: MealSlot) -> some View {
        if let meal = service.meal(on: day, slot: slot) {
            mealRow(meal)
        } else {
            Button {
                addTarget = MealAddTarget(day: day, slot: slot)
                HapticFeedback.impact(.light)
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: slot.icon)
                        .font(AppFont.scaled(14))
                        .foregroundStyle(slot.tint.opacity(AppOpacity.disabled))
                        .frame(width: 26)
                    Text(slot.label)
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.secondaryTextColor)
                    Spacer()
                    Image(systemName: "plus.circle")
                        .font(AppFont.scaled(17))
                        .foregroundStyle(Color.secondaryTextColor)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func mealRow(_ meal: MealPlan) -> some View {
        Button {
            editingMeal = meal
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle().fill(meal.slot.tint.opacity(AppOpacity.tintedFill))
                    Image(systemName: meal.slot.icon)
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(meal.slot.tint)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: meal.title)
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    if !meal.ingredients.isEmpty {
                        Text(String(format: String(localized: "meal_ingredients_count_fmt"),
                                    meal.ingredients.count))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
                Spacer()
                if meal.isCooked {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(Color.brandSuccess)
                        .accessibilityLabel(Text("meal_cooked"))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !meal.isCooked {
                Button {
                    Task { await service.markCooked(meal, pantry: pantryService) }
                    HapticFeedback.success()
                } label: { Label("meal_mark_cooked", systemImage: "checkmark.seal") }
            }
            if !meal.ingredients.isEmpty {
                Button {
                    dispatchSend(meal)
                } label: { Label("meal_send_shopping", systemImage: "cart.badge.plus") }
            }
            Button {
                editingMeal = meal
            } label: { Label("meal_edit", systemImage: "pencil") }
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task { await service.delete(meal) }
            } label: { Label("Remove", systemImage: "trash") }
        }
    }

    // MARK: Send to shopping

    /// One list → straight in; several → the dialog picks; none → a
    /// "Groceries" list is created first, so the action never dead-ends.
    private func dispatchSend(_ meal: MealPlan) {
        switch supplyService.lists.count {
        case 0:
            Task {
                guard let pid = propertyService.primary?.id,
                      let uid = supabase.auth.currentSession?.user.id else { return }
                let now = ISODate.string(from: Date())
                if let list = try? await supplyService.addList(NewSupplyListPayload(
                    propertyId: pid, ownerId: uid,
                    name: String(localized: "meal_groceries_list"),
                    icon: "cart.fill", color: "#34C759", note: nil,
                    createdAt: now, updatedAt: now)) {
                    await send(meal, to: list.id)
                }
            }
        case 1:
            Task { await send(meal, to: supplyService.lists[0].id) }
        default:
            sendMeal = meal
        }
    }

    private func send(_ meal: MealPlan, to listId: UUID) async {
        let added = await service.sendIngredients(of: meal, to: listId, supply: supplyService)
        sendMeal = nil
        if added > 0 { HapticFeedback.success() }
    }
}

// MARK: Add / edit sheet

struct MealFormSheet: View {
    @Environment(MealPlanService.self) private var service
    @Environment(\.dismiss) private var dismiss

    let day: Date
    let slot: MealSlot
    var editing: MealPlan?

    @State private var title = ""
    @State private var mealDay = Date()
    @State private var mealSlot: MealSlot = .dinner
    @State private var ingredients: [String] = []
    @State private var newIngredient = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var hydrated = false

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        FormScaffold(title: editing == nil ? "meal_add" : "meal_edit",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: mealSlot.icon, tint: mealSlot.tint) {
                    TextField("meal_title_ph", text: $title).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "calendar", tint: mealSlot.tint) {
                    DatePicker("meal_day", selection: $mealDay, displayedComponents: .date)
                        .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "fork.knife", tint: mealSlot.tint) {
                    Picker("meal_slot", selection: $mealSlot) {
                        ForEach(MealSlot.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "text.alignleft", tint: mealSlot.tint) {
                    TextField("meal_notes_ph", text: $notes).font(AppFont.body)
                }
            }

            FormGroup(title: "meal_ingredients_title") {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                    FormRow(icon: "circle.fill", tint: mealSlot.tint.opacity(AppOpacity.disabled)) {
                        Text(verbatim: ingredient).font(AppFont.body)
                        Spacer()
                        Button {
                            ingredients.remove(at: index)
                            HapticFeedback.impact(.light)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppFont.scaled(16))
                                .foregroundStyle(Color.secondaryTextColor)
                        }
                        .buttonStyle(.plain)
                    }
                    FormDivider()
                }
                FormRow(icon: "plus.circle", tint: mealSlot.tint) {
                    TextField("meal_ingredient_ph", text: $newIngredient)
                        .font(AppFont.body)
                        .onSubmit(addIngredient)
                        .submitLabel(.done)
                    if !newIngredient.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: addIngredient) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(AppFont.scaled(18))
                                .foregroundStyle(Color.brandSuccess)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        guard !hydrated else { return }
        hydrated = true
        if let meal = editing {
            title = meal.title
            mealDay = meal.date ?? day
            mealSlot = meal.slot
            ingredients = meal.ingredients
            notes = meal.notes ?? ""
        } else {
            mealDay = day
            mealSlot = slot
        }
    }

    private func addIngredient() {
        let name = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        ingredients.append(name)
        newIngredient = ""
        HapticFeedback.selection()
    }

    private func save() {
        // A typed-but-unconfirmed ingredient still counts — never lose input.
        addIngredient()
        let payload = MealPlanService.MealPayload(
            day: AppDate.dayString(from: mealDay),
            mealType: mealSlot.rawValue,
            title: title.trimmingCharacters(in: .whitespaces),
            ingredients: ingredients,
            notes: notes.isEmpty ? nil : notes)
        isSaving = true
        Task {
            do {
                if let meal = editing {
                    try await service.update(meal.id, payload: payload)
                } else {
                    try await service.add(payload)
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}
