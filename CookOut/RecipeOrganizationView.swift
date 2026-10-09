import SwiftUI

struct RecipeOrganizationView: View {
    @ObservedObject var store: NotesStore
    let browse: (RecipeCollectionRules, String?) -> Void
    @State private var tab: OrganizationTab = .overview
    @State private var editingCollection: RecipeSmartCollection?
    @State private var removingCollection: RecipeSmartCollection?
    @State private var editingTag: TagSelection?
    @State private var editingRecipe: CookingNote?
    @State private var query = ""
    @State private var limit = 40
    private enum OrganizationTab: String, CaseIterable, Identifiable {
        case overview = "Overview", collections = "Smart collections", tags = "Tags", duplicates = "Duplicates"
        var id: Self { self }
    }
    private struct TagSelection: Identifiable { let name: String; var id: String { name } }
    private var duplicateGroups: [RecipeDuplicateGroup] { RecipeOrganization.duplicates(in: store.notes) }
    private var tagRows: [(tag: String, count: Int)] { RecipeOrganization.tagCounts(in: store.notes).filter { query.isEmpty || $0.tag.localizedStandardContains(query) } }
    private var filingSuggestions: [(note: CookingNote, folder: RecipeFolder)] {
        store.notes.filter { $0.folderID == nil }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.compactMap {
            guard let folder = RecipeOrganization.suggestedFolder(for: $0, folders: store.folders) else { return nil }
            return ($0, folder)
        }
    }
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A cookbook you can find your way around", title: "Keep your recipes in order.", subtitle: "Curate smart collections, tidy tags, review similar recipes, and give unfiled recipes a home.")
                Picker("Organization section", selection: $tab) { ForEach(OrganizationTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                switch tab {
                case .overview: overview
                case .collections: collections
                case .tags: tags
                case .duplicates: duplicates
                }
            }
            .navigationTitle("Recipe organization")
            .sheet(item: $editingCollection) { collection in RecipeSmartCollectionEditor(store: store, collection: collection) }
            .sheet(item: $editingTag) { tag in RecipeTagRenameView(store: store, original: tag.name) }
            .sheet(item: $editingRecipe) { note in
                NoteEditor(note: note, folders: store.folders, availableTags: RecipeTags.available(in: store.notes), onSave: store.saveRecipe)
            }
            .alert("Remove smart collection?", isPresented: Binding(get: { removingCollection != nil }, set: { if !$0 { removingCollection = nil } }), presenting: removingCollection) { collection in
                Button("Remove collection", role: .destructive) { store.removeCollection(collection.id); removingCollection = nil }
                Button("Cancel", role: .cancel) { removingCollection = nil }
            } message: { _ in Text("This removes the saved filter. Recipes remain in your cookbook.") }
            .onChange(of: tab) { _, _ in query = ""; limit = 40 }
            .onChange(of: query) { _, _ in limit = 40 }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            CookOutPanel(title: "Your cookbook at a glance", symbol: "books.vertical") {
                Text("\(store.notes.count) recipes · \(store.folders.count) folders · \(RecipeTags.available(in: store.notes).count) tags · \(store.smartCollections.count) smart collections")
                Text("Open a group below to organize matching recipes together.").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                    overviewButton("Unfiled", symbol: "tray", rules: RecipeCollectionRules(unfiledOnly: true))
                    overviewButton("Without tags", symbol: "tag", rules: RecipeCollectionRules(details: .untagged))
                    overviewButton("Needs ingredients", symbol: "carrot", rules: RecipeCollectionRules(details: .missingIngredients))
                    overviewButton("Needs directions", symbol: "list.bullet", rules: RecipeCollectionRules(details: .missingDirections))
                    overviewButton("Never cooked", symbol: "flame", rules: RecipeCollectionRules(cookingHistory: .never))
                    overviewButton("Quick recipes", symbol: "clock", rules: RecipeCollectionRules(maxMinutes: 30))
                }
            }
            CookOutPanel(title: "Suggested homes for unfiled recipes", subtitle: "Suggestions use recipe titles and meal types. Review each destination before filing.", symbol: "folder.badge.plus") {
                let suggestions = filingSuggestions
                ForEach(suggestions.prefix(limit), id: \.note.id) { suggestion in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.note.title.isEmpty ? "Untitled recipe" : suggestion.note.title).font(.headline)
                            Text(RecipeFolders.path(for: suggestion.folder.id, in: store.folders)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("File here", systemImage: "folder") { store.fileSuggestedRecipe(suggestion.note, to: suggestion.folder.id) }.buttonStyle(.bordered).disabled(!store.isAvailable)
                    }.padding(.vertical, 5)
                }
                if suggestions.count > limit { Button("Show 40 more suggestions") { limit += 40 } }
                if suggestions.isEmpty { Text("No unfiled recipes have a clear category match. Choose a folder when saving a recipe or use bulk organization.").foregroundStyle(.secondary) }
            }
        }
    }
    private func overviewButton(_ title: String, symbol: String, rules: RecipeCollectionRules) -> some View {
        Button { browse(rules, nil) } label: {
            HStack { Label(title, systemImage: symbol); Spacer(); Text("\(rules.filter(store.notes, folders: store.folders).count)").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity).padding(10)
        }.buttonStyle(.bordered)
    }
    private var collections: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Collections update as recipes match their rules.").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("New smart collection", systemImage: "plus") { editingCollection = RecipeSmartCollection(name: "", rules: RecipeCollectionRules()) }.buttonStyle(.borderedProminent)
            }
            if store.smartCollections.isEmpty { Text("Try a collection for quick dinners, recipes you want to test, or family favorites with particular tags.").foregroundStyle(.secondary) }
            ForEach(store.smartCollections) { collection in
                CookOutPanel(title: collection.name, symbol: "rectangle.stack") {
                    Text("\(collection.rules.filter(store.notes, folders: store.folders).count) matching recipes").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button("Browse recipes", systemImage: "book.closed") { browse(collection.rules, collection.name) }.buttonStyle(.borderedProminent)
                        Button("Edit rules", systemImage: "slider.horizontal.3") { editingCollection = collection }.buttonStyle(.bordered)
                        Menu("More", systemImage: "ellipsis") { Button("Remove collection", role: .destructive) { removingCollection = collection } }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }
    private var tags: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Find a tag", text: $query).cookOutField()
            Text("Rename tags consistently across recipes and saved collections. Renaming to an existing tag combines their recipe memberships.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(tagRows.prefix(limit), id: \.tag) { row in
                CookOutPanel(title: "") {
                    HStack {
                        Label(row.tag, systemImage: "tag").font(.headline)
                        Text("\(row.count) recipes").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Browse") { browse(RecipeCollectionRules(tags: [row.tag]), nil) }.buttonStyle(.bordered)
                        Button("Rename or merge") { editingTag = TagSelection(name: row.tag) }.buttonStyle(.bordered)
                    }
                }
            }
            if tagRows.count > limit { Button("Show 40 more tags") { limit += 40 } }
            if tagRows.isEmpty { Text("No matching tags. Add tags in the recipe editor or select recipes and organize them together.").foregroundStyle(.secondary) }
        }
    }
    private var duplicates: some View {
        VStack(alignment: .leading, spacing: 18) {
            let groups = duplicateGroups
            Text("\(groups.count) groups to review. Matching source links can contain different versions; compare notes, ratings, and cooking history before deciding which to keep.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(groups.prefix(limit)) { group in
                CookOutPanel(title: "Similar recipes", subtitle: group.reason, symbol: "doc.on.doc") {
                    ForEach(group.recipes) { note in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title.isEmpty ? "Untitled recipe" : note.title).font(.headline)
                                Text("\(note.folderID.map { RecipeFolders.path(for: $0, in: store.folders) } ?? "Unfiled") · \(note.rating) stars · cooked \(note.cookCount) times").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Review recipe") { editingRecipe = note }.buttonStyle(.bordered)
                        }.padding(.vertical, 5)
                    }
                }
            }
            if groups.count > limit { Button("Show 40 more groups") { limit += 40 } }
            if groups.isEmpty { Text("No matching source links or exact recipe-content copies were found.").foregroundStyle(.secondary) }
        }
    }
}

private struct RecipeTagRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NotesStore
    let original: String
    @State private var name = ""
    @State private var failed = false
    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Consistent tags, easier browsing", title: "Rename “\(original)”.", subtitle: "All matching recipe tags and smart-collection rules are updated together.")
                TextField("New tag name", text: $name).cookOutField()
                let clean = RecipeTags.normalized([name]).first ?? ""
                if RecipeTags.available(in: store.notes).contains(where: { RecipeTags.key($0) == RecipeTags.key(clean) && RecipeTags.key($0) != RecipeTags.key(original) }) {
                    Label("This combines the tag with “\(clean)” and removes repeated tags within recipes.", systemImage: "arrow.triangle.merge").font(.subheadline)
                }
                if failed { Text(store.errorMessage ?? "The tag could not be renamed.").foregroundStyle(CookOutTheme.coral) }
            }
            .onAppear { name = original }
            .navigationTitle("Rename tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Rename tag") { if store.renameTag(original, to: name) { dismiss() } else { failed = true } }.disabled(RecipeTags.normalized([name]).isEmpty || !store.isAvailable) }
            }
        }.cookOutSheetFrame(width: 650, height: 450)
    }
}
