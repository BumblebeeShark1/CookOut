import SwiftUI

struct RecipeRulesFields: View {
    @Binding var rules: RecipeCollectionRules
    let folders: [RecipeFolder]
    var includeSearch = true
    @State private var tagsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if includeSearch {
                CookOutPanel(title: "Words, tags & location", symbol: "magnifyingglass") {
                    TextField("Search words or ingredients", text: $rules.query).cookOutField()
                    TextField("Required tags, separated by commas", text: $tagsText).cookOutField()
                    Text("Recipes must match every search word and every required tag.").font(.caption).foregroundStyle(.secondary)
                    Picker("Folder", selection: $rules.folderID) {
                        Text("All folders").tag(nil as UUID?)
                        if let id = rules.folderID, !folders.contains(where: { $0.id == id }) { Text("Folder no longer exists").tag(Optional(id)) }
                        ForEach(folders) { Text(RecipeFolders.path(for: $0.id, in: folders)).tag(Optional($0.id)) }
                    }.disabled(rules.unfiledOnly)
                    Toggle("Unfiled recipes only", isOn: $rules.unfiledOnly)
                        .onChange(of: rules.unfiledOnly) { _, value in if value { rules.folderID = nil } }
                }
            }
            CookOutPanel(title: "At the table", symbol: "fork.knife") {
                Picker("Meal", selection: $rules.meal) {
                    Text("Every meal").tag(nil as MealType?)
                    ForEach(MealType.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("Difficulty", selection: $rules.difficulty) {
                    Text("Any difficulty").tag(nil as RecipeDifficulty?)
                    ForEach(RecipeDifficulty.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                Toggle("Limit cooking time", isOn: Binding(get: { rules.maxMinutes != nil }, set: { rules.maxMinutes = $0 ? 30 : nil }))
                if rules.maxMinutes != nil {
                    Stepper("Up to \(rules.maxMinutes ?? 30) minutes", value: Binding(get: { rules.maxMinutes ?? 30 }, set: { rules.maxMinutes = $0 }), in: 5...1440, step: 5)
                    Text("Recipes with no reported time are excluded from this limit.").font(.caption).foregroundStyle(.secondary)
                }
            }
            CookOutPanel(title: "Your recipe journey", symbol: "bookmark") {
                Picker("Status", selection: $rules.status) {
                    Text("Any status").tag(nil as RecipeStatus?)
                    ForEach(RecipeStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                Picker("Cooking history", selection: $rules.cookingHistory) { ForEach(RecipeCookingFilter.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Recipe details", selection: $rules.details) { ForEach(RecipeDetailFilter.allCases) { Text($0.rawValue).tag($0) } }
                Stepper(rules.minimumRating == 0 ? "Any rating" : "At least \(rules.minimumRating) stars", value: $rules.minimumRating, in: 0...5)
                Toggle("Favorites only", isOn: $rules.favoritesOnly)
                Toggle("Pinned recipes only", isOn: $rules.pinnedOnly)
            }
        }
        .onAppear { tagsText = rules.tags.joined(separator: ", ") }
        .onChange(of: tagsText) { _, value in rules.tags = RecipeTags.parse(value) }
    }
}

struct RecipeSmartCollectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NotesStore
    @State var collection: RecipeSmartCollection
    var onSaved: ((RecipeSmartCollection) -> Void)?
    @State private var failed = false
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A collection that keeps itself current", title: "Save a smart collection.", subtitle: "Matching recipes appear automatically as your cookbook changes. Recipes keep their original folders.")
                CookOutPanel(title: "Collection name", symbol: "rectangle.stack") {
                    TextField("e.g. Quick weeknight favorites", text: $collection.name).cookOutField()
                    Text("\(collection.rules.filter(store.notes, folders: store.folders).count) recipes match right now").font(.caption).foregroundStyle(.secondary)
                }
                RecipeRulesFields(rules: $collection.rules, folders: store.folders)
                if failed { Text(store.errorMessage ?? "This collection could not be saved.").foregroundStyle(CookOutTheme.coral) }
            }
            .navigationTitle("Smart collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save collection") {
                        if store.saveCollection(collection) {
                            collection.name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSaved?(collection); dismiss()
                        } else { failed = true }
                    }.disabled(collection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.isAvailable)
                }
            }
        }.cookOutSheetFrame(width: 730, height: 850)
    }
}

struct RecipeFilterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rules: RecipeCollectionRules
    let folders: [RecipeFolder]
    let apply: (RecipeCollectionRules) -> Void
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Find the right recipe", title: "Narrow your cookbook.", subtitle: "Combine meal, time, rating, cooking history, and missing-detail filters with your current search and folder.")
                RecipeRulesFields(rules: $rules, folders: folders, includeSearch: false)
                Button("Reset these filters") { rules = RecipeCollectionRules() }.buttonStyle(.bordered)
            }
            .navigationTitle("Recipe filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply filters") { apply(rules); dismiss() } }
            }
        }.cookOutSheetFrame(width: 700, height: 800)
    }
}

struct RecipeBatchEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NotesStore
    let ids: Set<UUID>
    @State private var addTags = ""
    @State private var removeTags = ""
    @State private var changes = RecipeBatchChanges()
    @State private var failed = false
    var onApplied: (() -> Void)?
    private var proposed: RecipeBatchChanges {
        var copy = changes; copy.addTags = RecipeTags.parse(addTags); copy.removeTags = RecipeTags.parse(removeTags); return copy
    }
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Organize several recipes together", title: "Update \(ids.count) recipes.", subtitle: "Choose the fields to change. Each selected recipe keeps its ingredients, directions, and cooking history.")
                CookOutPanel(title: "Tags", symbol: "tag") {
                    TextField("Add tags, separated by commas", text: $addTags).cookOutField()
                    TextField("Remove tags, separated by commas", text: $removeTags).cookOutField()
                    Text("New tags join each recipe’s existing tags. A tag entered in both fields is kept.").font(.caption).foregroundStyle(.secondary)
                }
                CookOutPanel(title: "Folder & meal", symbol: "folder") {
                    Toggle("Move selected recipes", isOn: $changes.changeFolder)
                    if changes.changeFolder {
                        Picker("Destination", selection: $changes.folderID) {
                            Text("Unfiled").tag(nil as UUID?)
                            ForEach(store.folders) { Text(RecipeFolders.path(for: $0.id, in: store.folders)).tag(Optional($0.id)) }
                        }
                    }
                    Picker("Meal", selection: $changes.meal) {
                        Text("Keep each meal type").tag(nil as MealType?)
                        ForEach(MealType.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }
                CookOutPanel(title: "Status & favorites", symbol: "heart") {
                    Picker("Status", selection: $changes.status) {
                        Text("Keep each status").tag(nil as RecipeStatus?)
                        ForEach(RecipeStatus.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Favorites", selection: $changes.favorite) {
                        Text("Keep each setting").tag(nil as Bool?)
                        Text("Favorite all selected").tag(Optional(true))
                        Text("Remove favorites").tag(Optional(false))
                    }
                    Picker("Pins", selection: $changes.pinned) {
                        Text("Keep each setting").tag(nil as Bool?)
                        Text("Pin all selected").tag(Optional(true))
                        Text("Unpin all selected").tag(Optional(false))
                    }
                }
                if failed { Text(store.errorMessage ?? "No changes could be saved.").foregroundStyle(CookOutTheme.coral) }
            }
            .navigationTitle("Bulk organization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply to \(ids.count) recipes") { if store.organizeRecipes(ids, changes: proposed) { onApplied?(); dismiss() } else { failed = true } }
                        .disabled(!proposed.hasChanges || ids.isEmpty || !store.isAvailable)
                }
            }
        }.cookOutSheetFrame(width: 740, height: 800)
    }
}
