import SwiftUI

// MARK: - FishManagementView
//
// Tab-based view: Populations list + Species catalog + Fish journal timeline.
// Receives FishService as @ObservedObject from PondDashboardView (shared instance).

struct FishManagementView: View {
    let pond: Pond
    @ObservedObject var fishService: FishService
    @State private var selectedTab: FishTab = .populations
    @State private var showAddPopulation = false
    @State private var showAddJournalEntry = false
    @State private var searchText = ""

    enum FishTab: String, CaseIterable {
        case populations = "Populations"
        case species     = "Species"
        case journal     = "Journal"
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                tabPicker
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        switch selectedTab {
                        case .populations: populationsContent
                        case .species:     speciesContent
                        case .journal:     journalContent
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(pond.name + " — Fish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if selectedTab == .journal {
                        showAddJournalEntry = true
                    } else {
                        showAddPopulation = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showAddPopulation) {
            AddFishPopulationSheet(pond: pond, fishService: fishService)
        }
        .sheet(isPresented: $showAddJournalEntry) {
            AddJournalEntrySheet(pond: pond, fishService: fishService)
        }
        .task {
            try? await fishService.loadPopulations(for: pond.id)
            try? await fishService.loadJournal(for: pond.id)
        }
    }

    // MARK: Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(FishTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selectedTab == tab
                                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                                : nil
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.bottom, 16)
    }

    // MARK: Populations

    private var populationsContent: some View {
        VStack(spacing: 12) {
            if fishService.isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 60)
            } else if fishService.populations.isEmpty {
                emptyState(
                    icon: "fish.fill",
                    title: "No fish populations",
                    subtitle: "Add your first fish population to start tracking."
                )
            } else {
                biomassHeaderCard

                ForEach(fishService.populations) { pop in
                    PopulationRow(
                        population: pop,
                        species: fishService.species(id: pop.speciesId)
                    )
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 4)
    }

    private var biomassHeaderCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                biomassStatItem(
                    value: "\(fishService.totalFishCount)",
                    label: "Total Fish",
                    icon: "fish.fill",
                    color: Color(hex: "#30D158")
                )
                Divider()
                    .frame(width: 0.5, height: 44)
                    .background(Color.white.opacity(0.12))
                biomassStatItem(
                    value: String(format: "%.1f", fishService.estimatedBiomassKg()),
                    label: "Est. Biomass (kg)",
                    icon: "scalemass",
                    color: Color(hex: "#0A84FF")
                )
                Divider()
                    .frame(width: 0.5, height: 44)
                    .background(Color.white.opacity(0.12))
                biomassStatItem(
                    value: "\(fishService.populations.count)",
                    label: "Species Groups",
                    icon: "square.grid.2x2",
                    color: Color(hex: "#BF5AF2")
                )
            }
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }

    private func biomassStatItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Species

    private var speciesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
                .padding(.horizontal, 20)

            ForEach(filteredSpecies) { species in
                SpeciesCard(species: species, isOwned: fishService.populations.contains { $0.speciesId == species.id })
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 4)
    }

    private var filteredSpecies: [FishSpecies] {
        let catalog = fishService.builtInSpecies
        guard !searchText.isEmpty else { return catalog }
        return catalog.filter {
            $0.commonName.localizedCaseInsensitiveContains(searchText) ||
            $0.latinName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search species…", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    // MARK: Journal

    private var journalContent: some View {
        VStack(spacing: 0) {
            if fishService.journalEntries.isEmpty {
                emptyState(
                    icon: "book.pages",
                    title: "No journal entries",
                    subtitle: "Log fish events: stocking, observations, treatments."
                )
            } else {
                ForEach(fishService.journalEntries) { entry in
                    JournalEntryRow(
                        entry: entry,
                        species: entry.speciesId.flatMap { fishService.species(id: $0) }
                    )
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Empty State

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.2))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }
}

// MARK: - PopulationRow

private struct PopulationRow: View {
    let population: FishPopulation
    let species: FishSpecies?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#30D158").opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: species?.icon ?? "fish.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "#30D158"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(species?.commonName ?? population.speciesId)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                if let latin = species?.latinName {
                    Text(latin)
                        .font(.system(size: 11, weight: .regular))
                        .italic()
                        .foregroundStyle(.white.opacity(0.4))
                }

                HStack(spacing: 8) {
                    if let colorVariety = population.colorVariety {
                        Tag(text: colorVariety, color: Color(hex: "#BF5AF2"))
                    }
                    if let avgLen = population.averageLengthCm {
                        Tag(text: String(format: "~%.0f cm", avgLen), color: Color(hex: "#0A84FF"))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(population.estimatedCount)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("fish")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - SpeciesCard

private struct SpeciesCard: View {
    let species: FishSpecies
    let isOwned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(species.commonName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if isOwned {
                            Text("In Pond")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(hex: "#30D158"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(hex: "#30D158").opacity(0.15)))
                        }
                    }
                    Text(species.latinName)
                        .font(.system(size: 11)).italic()
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Tag(text: species.category.displayName, color: Color(hex: "#0A84FF"))
            }

            HStack(spacing: 0) {
                speciesParam("Temp", value: "\(Int(species.minTempC))–\(Int(species.maxTempC))°C", icon: "thermometer.medium")
                Spacer()
                speciesParam("pH", value: "\(species.minPh, specifier: "%.1f")–\(species.maxPh, specifier: "%.1f")", icon: "atom")
                Spacer()
                speciesParam("DO min", value: "\(species.minDissolvedOxygen, specifier: "%.1f") mg/L", icon: "bubbles.and.sparkles")
            }

            if let notes = species.notes {
                Text(notes)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func speciesParam(_ label: String, value: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - JournalEntryRow

private struct JournalEntryRow: View {
    let entry: FishJournalEntry
    let species: FishSpecies?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(entry.event.color.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: entry.event.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(entry.event.color)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.event.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(entry.recordedAt.relativeFormatted)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }

                if let count = entry.count {
                    Text("\(count) fish")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if let sp = species {
                    Text(sp.commonName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }

                if let notes = entry.notes {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(3)
                }
            }
            .padding(.bottom, 16)
        }
        .padding(.top, 4)
    }
}

// MARK: - Tag

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - AddFishPopulationSheet

struct AddFishPopulationSheet: View {
    let pond: Pond
    @ObservedObject var fishService: FishService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSpecies: FishSpecies?
    @State private var count = 10
    @State private var colorVariety = ""
    @State private var avgLengthCm = ""
    @State private var sourceNotes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Species picker
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Species")
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(fishService.builtInSpecies) { sp in
                                        speciesChip(sp)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            sectionLabel("Count")
                                .padding(.horizontal, 20)
                            Stepper("\(count) fish", value: $count, in: 1...10000, step: 1)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)

                            FormField(label: "Color Variety (optional)", text: $colorVariety, placeholder: "e.g. Kohaku, Sanke")
                            FormField(label: "Avg. Length cm (optional)", text: $avgLengthCm, placeholder: "e.g. 30", keyboardType: .decimalPad)
                            FormField(label: "Source Notes (optional)", text: $sourceNotes, placeholder: "e.g. Purchased from Yamaken Koi")
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Fish Population")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.6))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? Color(hex: "#30D158") : .white.opacity(0.3))
                        .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private var canSave: Bool { selectedSpecies != nil }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 20)
    }

    private func speciesChip(_ sp: FishSpecies) -> some View {
        let isSelected = selectedSpecies?.id == sp.id
        return Button {
            selectedSpecies = isSelected ? nil : sp
        } label: {
            VStack(spacing: 6) {
                Image(systemName: sp.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color(hex: "#30D158") : .white.opacity(0.5))
                Text(sp.commonName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color(hex: "#30D158").opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color(hex: "#30D158").opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let species = selectedSpecies else { return }
        isSaving = true
        Task {
            let pop = FishPopulation(
                pondId: pond.id,
                speciesId: species.id,
                estimatedCount: count,
                averageLengthCm: Double(avgLengthCm),
                colorVariety: colorVariety.isEmpty ? nil : colorVariety,
                sourceNotes: sourceNotes.isEmpty ? nil : sourceNotes
            )
            try? await fishService.addPopulation(pop)
            dismiss()
        }
    }
}

// MARK: - AddJournalEntrySheet

struct AddJournalEntrySheet: View {
    let pond: Pond
    @ObservedObject var fishService: FishService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEvent: FishEvent = .observation
    @State private var count = ""
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("Event Type")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(FishEvent.allCases, id: \.self) { event in
                                    eventChip(event)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        if selectedEvent == .stocking || selectedEvent == .harvest || selectedEvent == .death {
                            FormField(label: "Count", text: $count, placeholder: "Number of fish", keyboardType: .numberPad)
                        }

                        FormField(label: "Notes", text: $notes, placeholder: "Observations, treatments, details…", multiline: true)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Log Fish Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.6))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(Color(hex: "#30D158"))
                        .disabled(isSaving)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 20)
    }

    private func eventChip(_ event: FishEvent) -> some View {
        let isSelected = selectedEvent == event
        return Button {
            selectedEvent = event
        } label: {
            HStack(spacing: 8) {
                Image(systemName: event.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? event.color : .white.opacity(0.4))
                Text(event.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? event.color.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? event.color.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        isSaving = true
        Task {
            let entry = FishJournalEntry(
                pondId: pond.id,
                event: selectedEvent,
                count: Int(count),
                notes: notes.isEmpty ? nil : notes
            )
            try? await fishService.logEvent(entry)
            dismiss()
        }
    }
}

// MARK: - FormField helper (local, not a global component)

private struct FormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var multiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            Group {
                if multiline {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
        }
        .padding(.horizontal, 20)
    }
}
