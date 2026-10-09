import SwiftUI

struct RecipeBankView: View {
    @ObservedObject var bank: RecipeBankStore
    @ObservedObject var personal: NotesStore
    var onPlan: ((CookingNote) -> Void)?
    @State private var query = ""
    @State private var meal: MealType?
    @State private var cuisine: String?
    @State private var group: String?
    @State private var quickOnly = false
    @State private var limit = 40
    @State private var selected: BankRecipe?
    @State private var pendingPlan: CookingNote?
    @State private var selectingRecipes = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingImport = false
    @State private var selectionMessage: String?
    private var results: [BankRecipe] { bank.search(query: query, meal: meal, cuisine: cuisine, group: group, maxMinutes: quickOnly ? 30 : nil) }
    private var cuisines: [String] { Set(bank.recipes.map(\.cuisine)).sorted() }
    private var groups: [String] { Set(bank.recipes.flatMap(\.foodGroups)).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CookOutPageHeader(eyebrow: "A world of everyday food", title: "The recipe bank.",
                subtitle: "\(bank.recipes.count.formatted()) distinct recipes with ingredient lists and original-source links. Explore produce, whole grains, legumes, and flavors from many cuisines.")
            if let error = bank.errorMessage { Text(error).foregroundStyle(CookOutTheme.coral) }
            TextField("Find a dish, ingredient, cuisine, or publisher", text: $query).cookOutField()
            filters
            HStack {
                Text("\(results.count.formatted()) matches").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Clear filters") { query = ""; meal = nil; cuisine = nil; group = nil; quickOnly = false }
                    .buttonStyle(.borderless)
            }
            HStack {
                Button(selectingRecipes ? "Done selecting" : "Select recipes", systemImage: "checkmark.circle") {
                    selectingRecipes.toggle(); selectedIDs.removeAll(); selectionMessage = nil
                }.buttonStyle(.bordered)
                if selectingRecipes {
                    Text("\(selectedIDs.count) selected").font(.subheadline).foregroundStyle(.secondary)
                    Menu("Selection") {
                        Button("Select shown recipes") { selectShown() }
                        Button("Clear selection") { selectedIDs.removeAll() }
                    }.buttonStyle(.bordered)
                    Button("File selected recipes", systemImage: "folder.badge.plus") { showingImport = true }
                        .buttonStyle(.borderedProminent).disabled(selectedIDs.isEmpty || !personal.isAvailable)
                }
                Spacer(minLength: 0)
            }
            if let selectionMessage { Text(selectionMessage).font(.caption).foregroundStyle(CookOutTheme.coral) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                ForEach(results.prefix(limit)) { recipe in
                    Button {
                        if selectingRecipes { toggleSelection(recipe.id) } else { selected = recipe }
                    } label: {
                        bankCard(recipe).overlay(alignment: .topTrailing) {
                            if selectingRecipes { Image(systemName: selectedIDs.contains(recipe.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(CookOutTheme.olive).padding(12) }
                        }
                    }.buttonStyle(CookOutPressStyle())
                        .accessibilityAddTraits(selectedIDs.contains(recipe.id) ? .isSelected : [])
                }
            }
            if results.count > limit { Button("Show 40 more recipes") { limit += 40 }.buttonStyle(.bordered) }
            if results.isEmpty && bank.errorMessage == nil {
                CookOutEmptyState(symbol: "magnifyingglass", title: "Try another flavor.", message: "Change an ingredient, cuisine, or meal filter to explore the bank.")
            }
            attribution
        }
        .onChange(of: query) { _, _ in limit = 40 }
        .onChange(of: meal) { _, _ in limit = 40 }
        .onChange(of: cuisine) { _, _ in limit = 40 }
        .onChange(of: group) { _, _ in limit = 40 }
        .onChange(of: quickOnly) { _, _ in limit = 40 }
        .sheet(isPresented: $showingImport) {
            BankRecipeImportView(store: personal, recipes: selectedIDs.sorted { $0.uuidString < $1.uuidString }.compactMap { bank.recipe($0)?.note() }) {
                selectedIDs.removeAll(); selectingRecipes = false; selectionMessage = nil
            }
        }
        .sheet(item: $selected, onDismiss: {
            if let note = pendingPlan { pendingPlan = nil; onPlan?(note) }
        }) { recipe in
            BankRecipeDetail(recipe: recipe, personal: personal, onPlan: onPlan == nil ? nil : { pendingPlan = $0 })
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else if selectedIDs.count < 250 { selectedIDs.insert(id); selectionMessage = nil }
        else { selectionMessage = "Choose up to 250 recipes per import, then file another selection." }
    }
    private func selectShown() {
        let proposed = selectedIDs.union(results.prefix(limit).map(\.id))
        guard proposed.count <= 250 else { selectionMessage = "Choose up to 250 recipes per import, then file another selection."; return }
        selectedIDs = proposed; selectionMessage = nil
    }

    private var filters: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 14) {
            Picker("Meal", selection: $meal) {
                Text("Every meal").tag(nil as MealType?)
                ForEach(MealType.allCases.filter { $0 != .other }) { Text($0.rawValue).tag(Optional($0)) }
            }
            Picker("Cuisine", selection: $cuisine) {
                Text("Every cuisine").tag(nil as String?)
                ForEach(cuisines, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Picker("Ingredient group", selection: $group) {
                Text("Every food group").tag(nil as String?)
                ForEach(groups, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Toggle("30 minutes or less", isOn: $quickOnly)
        }.font(.subheadline)
    }

    private func bankCard(_ recipe: BankRecipe) -> some View {
        CookOutPanel(title: "") {
            HStack {
                Image(systemName: recipe.mealType.symbol).foregroundStyle(recipe.mealType.tint)
                Text(recipe.mealType.rawValue.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if personal.notes.contains(where: { $0.id == recipe.id }) { Image(systemName: "bookmark.fill").foregroundStyle(CookOutTheme.olive) }
            }
            Text(recipe.title).font(CookOutTypography.display(23, relativeTo: .title3)).foregroundStyle(.primary).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(recipe.foodGroups.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(recipe.cuisine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let minutes = recipe.totalMinutes { Label("\(minutes) min", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
            }
            Text(recipe.publisher).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var attribution: some View {
        CookOutPanel(title: "About this collection", symbol: "info.circle") {
            Text("Recipes are source-linked bookmarks: ingredient facts are available here, while directions remain at the publisher. The source catalog is historical, and recipe URLs or yields may have changed. Food-group labels are ingredient matches, not a nutrient analysis.")
                .font(.caption).foregroundStyle(.secondary)
            if let catalog = bank.catalog {
                Text(catalog.attribution).font(.caption2).foregroundStyle(.secondary)
                HStack {
                    if let url = RecipeSourceURL.valid(catalog.licenseURL) { Link("Catalog license", destination: url) }
                    if let url = RecipeSourceURL.valid(catalog.datasetURL) { Link("Dataset source", destination: url) }
                    if let url = RecipeSourceURL.valid(catalog.nutritionGuidanceURL) { Link("Balanced meal guidance", destination: url) }
                }.font(.caption)
            }
        }
    }
}

private struct BankRecipeDetail: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: BankRecipe
    @ObservedObject var personal: NotesStore
    var onPlan: ((CookingNote) -> Void)?
    @State private var saveFailed = false
    private var saved: Bool { personal.notes.contains { $0.id == recipe.id } }
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: recipe.publisher, title: recipe.title, subtitle: recipe.cuisine + " · " + recipe.mealType.rawValue)
                CookOutPanel(title: "At a glance", symbol: "leaf") {
                    Text(recipe.foodGroups.joined(separator: " · "))
                    Text(recipe.totalMinutes.map { "\($0) minutes reported by the source" } ?? "Cooking time not reported")
                    Text(recipe.servings.map { "Source yield: \($0) servings" } ?? "Source yield is unclear. Quantities cannot be scaled until you confirm servings.")
                    Text("Ingredient matches describe variety, not verified nutrient totals or allergen safety.").font(.caption).foregroundStyle(.secondary)
                }
                CookOutPanel(title: "Ingredient list", subtitle: "Check the original recipe for current amounts and directions.", symbol: "carrot") {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, line in Text("• " + line) }
                }
                CookOutPanel(title: "Cook it from the original", symbol: "safari") {
                    if let url = recipe.url { Link("Open \(recipe.publisher) recipe", destination: url).buttonStyle(.borderedProminent) }
                    Text("Publisher cooking instructions are not copied into the bank.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(saved ? "Already in your cookbook" : "Save to your cookbook", systemImage: "bookmark") {
                        if !personal.saveRecipe(recipe.note()) { saveFailed = true }
                    }.buttonStyle(.bordered).disabled(saved || !personal.isAvailable)
                    if let onPlan {
                        Button("Plan this recipe", systemImage: "calendar") { let note = recipe.note(); dismiss(); onPlan(note) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Recipe bank")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .alert("Recipe could not be saved", isPresented: $saveFailed) { Button("OK", role: .cancel) {} } message: { Text(personal.errorMessage ?? "Try again.") }
        }.cookOutSheetFrame(width: 720, height: 800)
    }
}

private struct BankRecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NotesStore
    let recipes: [CookingNote]
    let onImported: () -> Void
    @State private var folderID: UUID?
    @State private var tags = ""
    @State private var failed = false
    private var newRecipes: [CookingNote] { let existing = Set(store.notes.map(\.id)); return recipes.filter { !existing.contains($0.id) } }
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Build your own cookbook", title: "File recipes from the bank.", subtitle: "\(newRecipes.count) new recipes will be added. \(recipes.count - newRecipes.count) recipes already in your cookbook will keep their current edits, tags, and folders.")
                CookOutPanel(title: "Folder & tags", symbol: "folder") {
                    Picker("Save in", selection: $folderID) {
                        Text("Unfiled").tag(nil as UUID?)
                        ForEach(store.folders) { Text(RecipeFolders.path(for: $0.id, in: store.folders)).tag(Optional($0.id)) }
                    }
                    TextField("Extra tags, separated by commas", text: $tags).cookOutField()
                    Text("Cuisine and ingredient-group tags from the bank are retained. Cooking directions remain at each publisher.").font(.caption).foregroundStyle(.secondary)
                }
                CookOutPanel(title: "Your selection", symbol: "books.vertical") {
                    ForEach(recipes) { note in
                        HStack { Text(note.title); Spacer(); if !newRecipes.contains(where: { $0.id == note.id }) { Text("Already saved").font(.caption).foregroundStyle(.secondary) } }
                    }
                }
                if failed { Text(store.errorMessage ?? "Recipes could not be saved. Your cookbook is unchanged.").foregroundStyle(CookOutTheme.coral) }
            }
            .navigationTitle("File bank recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save \(newRecipes.count) recipes") {
                        if store.addRecipes(recipes, to: folderID, tags: RecipeTags.parse(tags)) { onImported(); dismiss() } else { failed = true }
                    }.disabled(newRecipes.isEmpty || !store.isAvailable)
                }
            }
        }.cookOutSheetFrame(width: 760, height: 800)
    }
}
