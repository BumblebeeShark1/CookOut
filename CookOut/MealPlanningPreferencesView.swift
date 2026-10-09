import SwiftUI

struct MealPlanningPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @State var preferences: PlanningPreferences
    let save: (PlanningPreferences) -> Bool
    @State private var exclusions = ""
    @State private var pantry = ""
    @State private var cuisineText = ""
    @State private var failed = false
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Plan around your life", title: "Your table, your preferences.", subtitle: "Balanced everyday food, with room for enjoyment. No diet program or weight-loss target.")
                CookOutPanel(title: "Household & cooking time", symbol: "person.2") {
                    Stepper("\(preferences.householdSize) people", value: $preferences.householdSize, in: 1...12)
                    Stepper("Up to \(preferences.maxCookingMinutes) minutes per recipe", value: $preferences.maxCookingMinutes, in: 10...240, step: 5)
                    Toggle("Allow recipes with an unknown cooking time", isOn: $preferences.allowUnknownTimes)
                    Toggle("Favor budget-minded ingredients and pantry reuse", isOn: $preferences.budgetMindful)
                    Toggle("Reserve dinner portions for next-day lunches", isOn: $preferences.useLeftovers)
                }
                CookOutPanel(title: "Meals to plan", symbol: "clock") {
                    ForEach(MealType.allCases.filter { $0 != .other }) { meal in
                        Toggle(meal.rawValue, isOn: Binding(get: { preferences.meals.contains(meal) }, set: { enabled in
                            if enabled { if !preferences.meals.contains(meal) { preferences.meals.append(meal) } }
                            else { preferences.meals.removeAll { $0 == meal } }
                        }))
                    }
                }
                CookOutPanel(title: "Ingredients to avoid", subtitle: "Separate items with commas or new lines.", symbol: "exclamationmark.circle") {
                    TextField("e.g. peanuts, shellfish, mushrooms", text: $exclusions, axis: .vertical).cookOutField()
                    Text("Exclusions check named ingredients and common aliases. Verify source recipes, packaged-food labels, and cross-contamination for allergies.").font(.caption).foregroundStyle(.secondary)
                }
                CookOutPanel(title: "Already in your pantry", subtitle: "These ingredients are favored in plans and omitted from the grocery list.", symbol: "cabinet") {
                    TextField("e.g. brown rice, chickpeas, olive oil", text: $pantry, axis: .vertical).cookOutField()
                }
                CookOutPanel(title: "Favorite cuisines", subtitle: "Optional preferences, with variety across the week.", symbol: "globe") {
                    TextField("e.g. Italian, Mexican, Indian", text: $cuisineText, axis: .vertical).cookOutField()
                }
                if failed { Text("Preferences could not be saved. Check the selected meals, input lengths, and storage access.").foregroundStyle(CookOutTheme.coral) }
            }
            .navigationTitle("Planning preferences")
            .onAppear {
                exclusions = preferences.avoidIngredients.joined(separator: ", ")
                pantry = preferences.pantryItems.joined(separator: ", ")
                cuisineText = preferences.preferredCuisines.joined(separator: ", ")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save preferences") {
                        preferences.avoidIngredients = Self.items(exclusions)
                        preferences.pantryItems = Self.items(pantry)
                        preferences.preferredCuisines = Self.items(cuisineText)
                        if save(preferences) { dismiss() } else { failed = true }
                    }.disabled(preferences.meals.isEmpty)
                }
            }
        }.cookOutSheetFrame(width: 740, height: 800)
    }
    private static func items(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: CharacterSet(charactersIn: ",\n")).compactMap {
            let item = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !item.isEmpty && seen.insert(RecipeIngredientIdentity.key(item)).inserted ? item : nil
        }
    }
}

struct MealPlanDraftReview: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: MealPlanDraft
    let candidates: [PlanningCandidate]
    let apply: (MealPlanDraft) -> Bool
    @State private var error: String?
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Review before saving", title: "Your next meals, proposed.", subtitle: draft.explanation)
                Label("Existing meals are preserved. This draft fills empty slots.", systemImage: "lock.shield")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(CookOutTheme.coral) }
                ForEach(draft.days.sorted(), id: \.self) { day in
                    CookOutPanel(title: MealPlanDate.date(day)?.formatted(date: .complete, time: .omitted) ?? day, symbol: "calendar") {
                        ForEach(draft.entries.filter { $0.day == day }) { meal in proposedRow(meal) }
                        if !draft.entries.contains(where: { $0.day == day }) { Text("Already planned.").foregroundStyle(.secondary) }
                    }
                }
                CookOutPanel(title: "Preparation outline", symbol: "checklist") {
                    ForEach(Array(draft.prepNotes.enumerated()), id: \.offset) { index, text in Text("\(index + 1). \(text)") }
                }
            }
            .navigationTitle("Meal-plan draft")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply \(draft.entries.count) meals") {
                        do {
                            try MealPlanningEngine.validateDraft(draft.entries, days: draft.days, candidates: candidates,
                                                                preferences: draft.preferences, occupied: draft.baseline)
                            if apply(draft) { dismiss() } else { error = "The plan could not be saved, or this week changed. Your existing meals are unchanged. Try generating a new draft." }
                        } catch { self.error = error.localizedDescription }
                    }.disabled(draft.entries.isEmpty)
                }
            }
        }.cookOutSheetFrame(width: 800, height: 850)
    }
    private func proposedRow(_ meal: PlannedMeal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(meal.meal.rawValue, systemImage: meal.meal.symbol).font(.caption.weight(.semibold))
                Spacer()
                Menu("Swap recipe", systemImage: "arrow.triangle.swap") {
                    ForEach(candidates.filter { candidate in
                        candidate.id != meal.recipeID && (candidate.note.mealType == meal.meal || candidate.note.mealType == .other) &&
                        (!draft.entries.contains(where: { $0.leftoversFromID == meal.id }) || candidate.note.canScaleQuantities)
                    }.prefix(15)) { candidate in
                        Button(candidate.note.title) { swap(meal, to: candidate.note) }
                    }
                }.font(.caption)
            }
            Text(meal.recipeTitle).font(.headline)
            Text("\(RecipeQuantity.format(meal.servings)) servings\(meal.leftoversFromID == nil ? "" : " · reserved leftovers")\(meal.preparedServings.map { " · prepare \(RecipeQuantity.format($0)) servings" } ?? "")")
                .font(.caption).foregroundStyle(.secondary)
            if let notes = meal.notes, !notes.isEmpty { Text(notes).font(.caption).foregroundStyle(.secondary) }
            if let source = meal.recipeSnapshot?.sourceURL, let url = RecipeSourceURL.valid(source) {
                Link("Original recipe · \(meal.recipeSnapshot?.sourcePublisher ?? "publisher")", destination: url).font(.caption)
            }
            Divider()
        }
    }
    private func swap(_ meal: PlannedMeal, to note: CookingNote) {
        guard let index = draft.entries.firstIndex(where: { $0.id == meal.id }) else { return }
        let oldParent = draft.entries[index].leftoversFromID
        draft.entries[index].recipeID = note.id
        draft.entries[index].recipeTitle = note.title
        draft.entries[index].recipeSnapshot = note
        draft.entries[index].leftoversFromID = nil
        draft.entries[index].notes = nil
        for child in draft.entries.indices where draft.entries[child].leftoversFromID == meal.id {
            draft.entries[child].recipeID = note.id
            draft.entries[child].recipeTitle = note.title
            draft.entries[child].recipeSnapshot = note
        }
        if let oldParent, let parent = draft.entries.firstIndex(where: { $0.id == oldParent }) {
            draft.entries[parent].preparedServings = draft.entries[parent].servings + draft.entries.filter { $0.leftoversFromID == oldParent }.reduce(0) { $0 + $1.servings }
        }
        error = nil
    }
}
