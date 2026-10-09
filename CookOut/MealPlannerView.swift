import SwiftUI

struct MealPlannerView: View {
    @ObservedObject var recipes: NotesStore
    @ObservedObject var bank: RecipeBankStore
    @StateObject private var plan = MealPlanStore()
    @State private var anchorDate = Date.now
    @State private var editingMeal: PlannedMeal?
    @State private var cooking: PlannedCooking?
    @State private var showingPreferences = false
    @State private var draft: MealPlanDraft?
    @State private var draftCandidates: [PlanningCandidate] = []
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>?
    @State private var selectedTab: PlannerTab = .week
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum PlannerTab: String, CaseIterable, Identifiable {
        case week = "Your week", bank = "Recipe bank", groceries = "Grocery list", prep = "Prep & variety"
        var id: Self { self }
    }
    private var weekStart: Date { Calendar.current.dateInterval(of: .weekOfYear, for: anchorDate)?.start ?? Calendar.current.startOfDay(for: anchorDate) }
    private var days: [Date] { (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) } }
    private var dayKeys: [String] { days.map { MealPlanDate.key($0) } }
    private var weekEntries: [PlannedMeal] { plan.entries.filter { dayKeys.contains($0.day) } }
    private var groceries: [GroceryItem] { MealPlanGroceries.build(entries: weekEntries, personal: recipes.notes, bank: bank.recipes, pantry: plan.preferences.pantryItems) }
    private var emptySlots: Int {
        dayKeys.reduce(0) { count, day in count + plan.preferences.meals.filter { meal in !weekEntries.contains { $0.day == day && $0.meal == meal } }.count }
    }

    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A well-fed week", title: "Plan meals worth looking forward to.",
                    subtitle: "Your cookbook, a \(bank.recipes.count.formatted())-recipe bank, pantry-aware planning, and a practical grocery list. Varied everyday meals, without a restrictive diet.")
                weekNavigation
                planningActions
                Picker("Planner section", selection: $selectedTab) {
                    ForEach(PlannerTab.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if !plan.isAvailable {
                    CookOutPanel(title: "Your saved plan needs attention", symbol: "exclamationmark.triangle") {
                        Text("Editing is paused while the saved plan cannot be read. The original file is preserved.").foregroundStyle(.secondary)
                        Button("Reload meal plan", systemImage: "arrow.clockwise") { plan.reload() }.buttonStyle(.borderedProminent)
                    }
                }
                switch selectedTab {
                case .week:
                    ForEach(days, id: \.self) { day in dayPanel(day) }
                case .bank:
                    RecipeBankView(bank: bank, personal: recipes) { note in addMeal(note: note, on: anchorDate) }
                case .groceries:
                    shoppingList
                case .prep:
                    preparationAndVariety
                }
            }
            .navigationTitle("Meal planner")
            .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: anchorDate)
            .sheet(item: $editingMeal) { meal in
                PlannedMealEditor(meal: meal, personal: recipes.notes, bank: bank, exclusions: plan.preferences.avoidIngredients) { plan.save($0) }
            }
            .sheet(isPresented: $showingPreferences) {
                MealPlanningPreferencesView(preferences: plan.preferences, save: plan.savePreferences)
            }
            .sheet(item: $draft) { draft in
                MealPlanDraftReview(draft: draft, candidates: draftCandidates, apply: plan.apply)
            }
            .sheet(item: $cooking) { value in
                CookingModeView(note: value.note, initialServings: value.servings) {
                    if recipes.notes.contains(where: { $0.id == value.note.id }) { recipes.markCooked(value.note) }
                    plan.setCompleted(value.id, completed: true)
                }
            }
            .alert("Meal planner", isPresented: Binding(get: { editingMeal == nil && draft == nil && plan.errorMessage != nil }, set: { if !$0 { plan.errorMessage = nil } })) {
                Button("OK", role: .cancel) { plan.errorMessage = nil }
            } message: { Text(plan.errorMessage ?? "") }
        }
        .onAppear { plan.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { plan.reload() } }
        .onDisappear { generationTask?.cancel(); generationTask = nil; isGenerating = false }
    }

    private var weekNavigation: some View {
        ViewThatFits(in: .horizontal) {
            HStack { weekControls; Spacer(); summary }
            VStack(alignment: .leading, spacing: 12) { weekControls; summary }
        }
    }
    private var weekControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { previousWeek; weekDate; nextWeek; today }
            VStack(alignment: .leading, spacing: 12) { weekDate; HStack { previousWeek; today; nextWeek } }
        }.buttonStyle(.bordered)
    }
    private var weekDate: some View { DatePicker("Week of", selection: $anchorDate, displayedComponents: .date).fixedSize() }
    private var previousWeek: some View { Button { changeWeek(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous week") }
    private var nextWeek: some View { Button { changeWeek(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next week") }
    private var today: some View { Button("Today") { anchorDate = .now } }
    private var summary: some View {
        Text("\(weekEntries.count) meals · \(weekEntries.filter { $0.isCompleted == true }.count) cooked · \(emptySlots) open slots")
            .font(.subheadline).foregroundStyle(.secondary)
    }
    private var planningActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { plannerButtons }
                VStack(alignment: .leading, spacing: 12) { plannerButtons }
            }
            if isGenerating {
                HStack { ProgressView().controlSize(.small); Text("Preparing a reviewable draft…"); Button("Cancel") { generationTask?.cancel() } }
                    .font(.subheadline)
            }
            Text("Local planning stays on this device. GPT-OSS planning sends your preferences and shortlisted recipe ingredients to Groq, then returns a draft for review.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var plannerButtons: some View {
        Button("Draft locally", systemImage: "leaf") { generate(usingAI: false) }
            .buttonStyle(.borderedProminent).disabled(isGenerating || !plan.isAvailable || emptySlots == 0)
        Button("Plan with GPT-OSS 120B", systemImage: "sparkles") { generate(usingAI: true) }
            .buttonStyle(.bordered).disabled(isGenerating || !plan.isAvailable || emptySlots == 0)
        Button("Preferences & pantry", systemImage: "slider.horizontal.3") { showingPreferences = true }
            .buttonStyle(.bordered).disabled(!plan.isAvailable)
        Menu("More", systemImage: "ellipsis") {
            Button("Copy meals to next week", systemImage: "doc.on.doc") { if plan.copyWeek(from: dayKeys) { changeWeek(1) } }
                .disabled(weekEntries.isEmpty || !plan.isAvailable)
            Button("Browse recipe bank", systemImage: "books.vertical") { selectedTab = .bank }
            Button("Reload plan", systemImage: "arrow.clockwise") { plan.reload() }
        }.buttonStyle(.bordered)
    }

    private func dayPanel(_ date: Date) -> some View {
        let entries = weekEntries.filter { $0.day == MealPlanDate.key(date) }.sorted {
            (MealType.allCases.firstIndex(of: $0.meal) ?? 0) < (MealType.allCases.firstIndex(of: $1.meal) ?? 0)
        }
        return CookOutPanel(title: "") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(date.formatted(.dateTime.weekday(.wide))).font(CookOutTypography.display(25, relativeTo: .title2))
                    Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if Calendar.current.isDateInToday(date) { Text("TODAY").font(.caption2.weight(.semibold)).foregroundStyle(CookOutTheme.olive) }
                Button("Add meal", systemImage: "plus") { addMeal(on: date) }.buttonStyle(.bordered)
                    .disabled(!plan.isAvailable || (recipes.notes.isEmpty && bank.recipes.isEmpty))
            }
            if entries.isEmpty { Text("Choose a recipe or let the planner suggest a draft.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(entries) { meal in Divider(); mealRow(meal) }
        }
    }
    private func mealRow(_ meal: PlannedMeal) -> some View {
        let note = MealPlanningEngine.resolve(meal, personal: recipes.notes, bank: bank.recipes)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: meal.isCompleted == true ? "checkmark.circle.fill" : meal.meal.symbol)
                    .foregroundStyle(meal.meal.tint).frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(meal.recipeTitle).font(.headline)
                    Text("\(meal.meal.rawValue) · \(RecipeQuantity.format(meal.servings)) servings\(meal.leftoversFromID == nil ? "" : " · leftovers")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let portions = meal.preparedServings, portions > meal.servings {
                        Text("Prepare \(RecipeQuantity.format(portions)) servings, reserving extra portions.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let publisher = note?.sourcePublisher { Text(publisher + " · source-linked recipe").font(.caption).foregroundStyle(.secondary) }
                    if let notes = meal.notes, !notes.isEmpty { Text(notes).font(.caption).foregroundStyle(.secondary) }
                    if note == nil { Text("Recipe unavailable. Choose a replacement.").font(.caption).foregroundStyle(CookOutTheme.coral) }
                }
                Spacer(minLength: 0)
                if meal.isLocked == true { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                Menu {
                    Button("Edit or swap recipe", systemImage: "arrow.triangle.swap") { editingMeal = meal }.disabled(meal.isLocked == true)
                    Button(meal.isLocked == true ? "Unlock meal" : "Lock meal", systemImage: "lock") { plan.setLocked(meal.id, locked: meal.isLocked != true) }
                    Button(meal.isCompleted == true ? "Mark not cooked" : "Mark cooked", systemImage: "checkmark.circle") { plan.setCompleted(meal.id, completed: meal.isCompleted != true) }
                    Menu("Move to day", systemImage: "calendar") {
                        ForEach(days, id: \.self) { day in
                            Button(day.formatted(.dateTime.weekday(.wide))) { plan.move(meal, to: MealPlanDate.key(day), mealType: meal.meal) }
                        }
                    }.disabled(meal.isLocked == true)
                    Button("Remove from plan", systemImage: "trash", role: .destructive) { plan.remove(meal) }.disabled(meal.isLocked == true)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    .disabled(!plan.isAvailable).accessibilityLabel("Options for \(meal.recipeTitle)")
            }
            if let note {
                HStack {
                    Button("Cooking checklist", systemImage: "fork.knife") {
                        cooking = PlannedCooking(id: meal.id, note: note, servings: meal.preparedServings ?? meal.servings)
                    }.buttonStyle(.bordered)
                    if let source = note.sourceURL, let url = RecipeSourceURL.valid(source) { Link("Original directions", destination: url).font(.subheadline) }
                }.padding(.leading, 42)
            }
        }
    }

    private var shoppingList: some View {
        VStack(alignment: .leading, spacing: 18) {
            CookOutPageHeader(eyebrow: "One list for the week", title: "Shop for what you’ll cook.", subtitle: "Quantities combine only when ingredient names and units match. Pantry items are omitted, and reserved leftovers are not counted twice.")
            HStack {
                Text("\(groceries.count) ingredients to check").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                ShareLink(item: groceryText) { Label("Share grocery list", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
            }
            if groceries.isEmpty { Text("Plan some meals to build a grocery list, or check whether your pantry covers the ingredients.").foregroundStyle(.secondary) }
            ForEach(groceries) { item in
                Button { plan.toggleGrocery(groceryKey(item)) } label: {
                    CookOutPanel(title: "") {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: plan.checkedGroceryKeys.contains(groceryKey(item)) ? "checkmark.circle.fill" : "circle").foregroundStyle(CookOutTheme.olive)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.ingredient).font(.headline).foregroundStyle(.primary)
                                Text(item.displayAmount).font(.subheadline).foregroundStyle(.secondary)
                                Text(item.mealTitles.sorted().joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                if item.needsSourceCheck { Text(item.originalLines.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                    }
                }.buttonStyle(CookOutPressStyle()).disabled(!plan.isAvailable)
            }
            Text("Unclear yields, ranges, and unmeasured ingredients require checking the recipe. Mass and volume are never combined using an invented density.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var preparationAndVariety: some View {
        let notes = weekEntries.compactMap { MealPlanningEngine.resolve($0, personal: recipes.notes, bank: bank.recipes) }
        let groups = ["Vegetables", "Fruit", "Whole grains", "Beans & lentils", "Protein foods", "Nuts & seeds"]
        return VStack(alignment: .leading, spacing: 22) {
            CookOutPageHeader(eyebrow: "Make the week easier", title: "Prep together. Eat with variety.", subtitle: "Ingredient variety and a practical routine, without invented calorie or nutrient totals.")
            CookOutPanel(title: "Foods represented in your plan", symbol: "leaf") {
                ForEach(groups, id: \.self) { group in
                    let count = notes.filter { RecipeFoodGroups.infer($0.ingredients).contains(group) }.count
                    HStack { Text(group); Spacer(); Text("\(count) meals").foregroundStyle(.secondary) }
                }
                Text("These are ingredient matches, not serving sizes or a measure of nutritional adequacy. Consider produce and a whole-grain side when a meal lacks them.").font(.caption).foregroundStyle(.secondary)
                Text("\(Set(notes.map(\.id)).count) distinct recipes · \(Set(notes.flatMap(\.ingredients).map { RecipeIngredientIdentity.key($0) }).count) distinct ingredient lines")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let outline = plan.prepNotesByWeek[MealPlanDate.key(weekStart)], !outline.isEmpty {
                CookOutPanel(title: "Your plan’s preparation outline", symbol: "list.bullet.clipboard") {
                    ForEach(Array(outline.enumerated()), id: \.offset) { index, text in Text("\(index + 1). \(text)") }
                }
            }
            CookOutPanel(title: "Preparation checklist", symbol: "checklist") {
                Text("1. Read each recipe’s current directions and serving yield before shopping.")
                Text("2. Check your pantry and consolidate the grocery list.")
                Text("3. Wash and chop vegetables for the next cooking session.")
                Text("4. Batch-cook grains or beans when your selected recipes call for them.")
                Text("5. Portion reserved leftovers separately and verify safe cooling and storage.")
            }
            CookOutPanel(title: "Meals to prepare ahead", symbol: "refrigerator") {
                ForEach(weekEntries.filter { ($0.preparedServings ?? $0.servings) > $0.servings }) { meal in
                    Text("\(meal.recipeTitle): prepare \(RecipeQuantity.format(meal.preparedServings!)) servings on \(meal.day).")
                }
                if !weekEntries.contains(where: { $0.leftoversFromID != nil }) { Text("No reserved leftovers this week. Enable next-day lunch portions in preferences.").foregroundStyle(.secondary) }
            }
            Link("Balanced meal guidance from Canada’s food guide", destination: URL(string: "https://www.canada.ca/en/health-canada/services/food-guide/eating-support/cooking/make-healthy-meals-plate.html")!).font(.caption)
        }
    }

    private func groceryKey(_ item: GroceryItem) -> String { MealPlanDate.key(weekStart) + "|" + item.id + "|" + item.displayAmount }
    private var groceryText: String { "CookOut grocery list — week of \(MealPlanDate.key(weekStart))\n\n" + groceries.map { "\(plan.checkedGroceryKeys.contains(groceryKey($0)) ? "✓" : "☐") \($0.ingredient) — \($0.displayAmount)" }.joined(separator: "\n") }
    private func changeWeek(_ amount: Int) { if let next = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: anchorDate) { anchorDate = next } }
    private func addMeal(on date: Date) {
        guard let note = recipes.notes.first ?? bank.recipes.first?.note() else { return }
        addMeal(note: note, on: date)
    }
    private func addMeal(note: CookingNote, on date: Date) {
        editingMeal = PlannedMeal(day: MealPlanDate.key(date), meal: note.mealType == .other ? .dinner : note.mealType,
            recipeID: note.id, recipeTitle: note.title, servings: Double(plan.preferences.householdSize), recipeSnapshot: note)
    }
    private func generate(usingAI: Bool) {
        guard !isGenerating, plan.isAvailable else { return }
        isGenerating = true
        let requestedDays = dayKeys, baseline = weekEntries, preferences = plan.preferences
        generationTask = Task { @MainActor in
            defer { isGenerating = false; generationTask = nil }
            do {
                try preferences.validate()
                let candidates = MealPlanningEngine.candidates(personal: recipes.notes, bank: bank.recipes, preferences: preferences)
                let proposal = usingAI ? try await GroqMealPlanService().draft(days: requestedDays, existing: baseline, candidates: candidates, preferences: preferences) : try MealPlanningEngine.generate(days: requestedDays, existing: baseline, candidates: candidates, preferences: preferences)
                try Task.checkCancellation()
                draftCandidates = candidates
                draft = proposal
            } catch is CancellationError { }
            catch { plan.errorMessage = error.localizedDescription }
        }
    }
}

private struct PlannedCooking: Identifiable {
    let id: UUID
    let note: CookingNote
    let servings: Double
}

private struct PlannedMealEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var meal: PlannedMeal
    let personal: [CookingNote]
    @ObservedObject var bank: RecipeBankStore
    let exclusions: [String]
    let save: (PlannedMeal) -> Bool
    @State private var query = ""
    @State private var useBank = false
    @State private var selectedNote: CookingNote?
    @State private var failed = false
    @State private var limit = 50
    private var note: CookingNote? { selectedNote ?? personal.first { $0.id == meal.recipeID } ?? meal.recipeSnapshot ?? bank.recipe(meal.recipeID)?.note() }
    private var date: Binding<Date> { Binding(get: { MealPlanDate.date(meal.day) ?? .now }, set: { meal.day = MealPlanDate.key($0) }) }
    private var candidates: [CookingNote] {
        if useBank { return Array(bank.search(query: query, meal: meal.meal).prefix(limit)).map { $0.note() } }
        return personal.filter { query.isEmpty || RecipeIngredientIdentity.key($0.title + " " + $0.ingredients.joined(separator: " ")).contains(RecipeIngredientIdentity.key(query)) }
    }
    private var valid: Bool { note != nil && meal.servings.isFinite && (0.25...24).contains(meal.servings) && !(note.map { IngredientExclusions.matches($0.ingredients, excluded: exclusions) } ?? true) }
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A place at the table", title: "Choose a meal.", subtitle: "Use your own cookbook or the source-linked bank, and plan portions for your household.")
                if failed { Text("This meal could not be saved. The existing plan is unchanged.").foregroundStyle(CookOutTheme.coral) }
                CookOutPanel(title: "Day, meal & portions", symbol: "calendar") {
                    DatePicker("Day", selection: date, displayedComponents: .date)
                    Picker("Meal", selection: $meal.meal) { ForEach(MealType.allCases) { Text($0.rawValue).tag($0) } }
                    Stepper("\(RecipeQuantity.format(meal.servings)) servings", value: $meal.servings, in: 0.25...24, step: 0.25)
                    if let note {
                        Text("Selected: \(note.title)").font(.headline)
                        if !note.canScaleQuantities { Text("Source yield unclear: grocery quantities cannot be scaled for these portions yet.").font(.caption).foregroundStyle(.secondary) }
                        if IngredientExclusions.matches(note.ingredients, excluded: exclusions) { Text("This recipe contains a named ingredient you chose to avoid.").font(.caption).foregroundStyle(CookOutTheme.coral) }
                    }
                    TextField("Meal notes or preparation reminders", text: Binding(get: { meal.notes ?? "" }, set: { meal.notes = $0 }), axis: .vertical).cookOutField()
                }
                CookOutPanel(title: "Find a recipe", symbol: "books.vertical") {
                    Picker("Recipe source", selection: $useBank) { Text("Your cookbook").tag(false); Text("Recipe bank").tag(true) }.pickerStyle(.segmented)
                    TextField("Title or ingredient", text: $query).cookOutField()
                    ForEach(candidates) { candidate in
                        Button { selectedNote = candidate; meal.recipeID = candidate.id; meal.recipeSnapshot = candidate } label: {
                            HStack(spacing: 12) {
                                Image(systemName: meal.recipeID == candidate.id ? "checkmark.circle.fill" : "circle").foregroundStyle(CookOutTheme.olive)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.title).font(.headline).foregroundStyle(.primary)
                                    Text(candidate.sourcePublisher ?? "Your cookbook").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.padding(.vertical, 8)
                        }.buttonStyle(CookOutPressStyle())
                    }
                    if useBank && candidates.count >= limit { Button("Show more") { limit += 50 } }
                    if candidates.isEmpty { Text("No matching recipes. Try another meal type or search.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Plan a meal")
            .onAppear { useBank = personal.isEmpty || !personal.contains(where: { $0.id == meal.recipeID }) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save meal") {
                        guard let note else { return }
                        meal.recipeTitle = String((note.title.isEmpty ? "Untitled recipe" : note.title).prefix(500))
                        meal.recipeSnapshot = note
                        if save(meal) { dismiss() } else { failed = true }
                    }.disabled(!valid)
                }
            }
        }.cookOutSheetFrame(width: 740, height: 800)
    }
}
