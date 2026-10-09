import SwiftUI
import UniformTypeIdentifiers

private enum CookOutDestination: String, CaseIterable, Identifiable {
    case recipes = "Recipe library", favorites = "Favorites", collections = "Folders", organization = "Organization", assistant = "CookAssistant", planner = "Meal planner", bank = "Recipe bank", tools = "Kitchen tools", appearance = "Appearance"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .recipes: "book.closed"
        case .favorites: "heart"
        case .collections: "square.grid.2x2"
        case .organization: "tray.full"
        case .assistant: "sparkles"
        case .planner: "calendar"
        case .bank: "books.vertical"
        case .tools: "scalemass"
        case .appearance: "slider.horizontal.3"
        }
    }
}

private struct RecipeEditorPresentation: Identifiable {
    let id = UUID()
    let note: CookingNote?
    let folderID: UUID?
}

struct ContentView: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private enum NoteSort: String, CaseIterable, Identifiable {
        case updated = "Recently edited", title = "Title", rating = "Highest rated", cooked = "Most cooked", quickest = "Quickest"
        var id: Self { self }
    }

    @StateObject private var store = NotesStore()
    @StateObject private var recipeBank = RecipeBankStore()
    @State private var destination: CookOutDestination? = .recipes
    @State private var query = ""
    @State private var editorPresentation: RecipeEditorPresentation?
    @State private var selectedTags: Set<String> = []
    @State private var searchAllFolders = true
    @FocusState private var searchIsFocused: Bool
    @State private var selectedFolder: RecipeFolderScope = .all
    @State private var sort: NoteSort = .updated
    @State private var favoritesOnly = false
    @State private var cookingNote: CookingNote?
    @State private var showingNotesImport = false
    @State private var showingNewFolder = false
    @State private var editingFolder: RecipeFolder?
    @State private var folderToRemove: RecipeFolder?
    @State private var advancedRules = RecipeCollectionRules()
    @State private var activeSmartCollectionID: UUID?
    @State private var showingRecipeFilters = false
    @State private var editingSmartCollection: RecipeSmartCollection?
    @State private var smartCollectionToRemove: RecipeSmartCollection?
    @State private var showingBatchEditor = false
    @State private var selectingRecipes = false
    @State private var selectedRecipeIDs: Set<UUID> = []
    @State private var showingLibraryImport = false
    @State private var showingLibraryExport = false
    @State private var libraryDocument = RecipeLibraryDocument(data: Data())
    @AppStorage("cookout.libraryGrid") private var usesGrid = true

    private var allTags: [String] {
        RecipeTags.available(in: store.notes)
    }

    private var filteredNotes: [CookingNote] {
        let filtered = RecipeLibrarySearch.filter(store.notes, folders: store.folders, query: query,
                                                   tags: selectedTags, folderScope: selectedFolder,
                                                   searchAllFolders: searchAllFolders, favoritesOnly: favoritesOnly)
        return filtered.filter { advancedRules.matches($0) }.sorted { first, second in
            if first.isPinned != second.isPinned { return first.isPinned }
            switch sort {
            case .updated: return first.updatedAt > second.updatedAt
            case .title: return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            case .rating: return first.rating > second.rating
            case .cooked: return first.cookCount > second.cookCount
            case .quickest:
                if first.totalMinutes == 0 { return false }
                if second.totalMinutes == 0 { return true }
                return first.totalMinutes < second.totalMinutes
            }
        }
    }

    private var hasSearchFilters: Bool { RecipeLibrarySearch.isActive(query: query, tags: selectedTags) || advancedRules.isActive }

    private var currentRules: RecipeCollectionRules {
        var rules = advancedRules
        rules.query = query; rules.tags = RecipeTags.normalized(Array(selectedTags).sorted())
        rules.favoritesOnly = favoritesOnly
        let across = searchAllFolders && RecipeLibrarySearch.isActive(query: query, tags: selectedTags)
        rules.folderID = across ? nil : initialFolderID
        rules.unfiledOnly = !across && selectedFolder == .unfiled
        return rules
    }
    private var currentCollection: RecipeSmartCollection? {
        store.smartCollections.first { $0.id == activeSmartCollectionID && $0.rules.equivalent(to: currentRules) }
    }

    private var resultsTitle: String {
        currentCollection?.name ?? (RecipeLibrarySearch.isActive(query: query, tags: selectedTags) && searchAllFolders ? "Across all folders" : activeFolderName)
    }

    private var activeFolderName: String {
        switch selectedFolder {
        case .all: favoritesOnly ? "Your favorites" : "Recipe library"
        case .unfiled: "Unfiled"
        case .folder(let id): store.folders.first(where: { $0.id == id })?.name ?? "All Recipes"
        }
    }

    private var initialFolderID: UUID? {
        if case .folder(let id) = selectedFolder { return id }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch destination ?? .recipes {
            case .recipes, .favorites: library
            case .collections: FolderManagerView(embedded: true, store: store, onOpenFolder: openFolder)
            case .organization: RecipeOrganizationView(store: store, browse: openRules)
            case .assistant: CookingChatView(embedded: true, cookbook: store.notes, folders: store.folders, bank: recipeBank.recipes, onSaveRecipe: store.saveRecipe)
            case .planner: MealPlannerView(recipes: store, bank: recipeBank)
            case .bank: NavigationStack { CookOutScreen { RecipeBankView(bank: recipeBank, personal: store) }.navigationTitle("Recipe bank") }
            case .tools: KitchenToolsView(recipes: store.notes)
            case .appearance: AppearanceSettingsView(embedded: true)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: destination)
        .tint(palette.accent)
        .sheet(isPresented: $showingNewFolder) {
            FolderEditor(title: "New folder", folders: store.folders, initialParentID: initialFolderID) { name, symbol, color, parent in
                store.createFolder(name: name, symbol: symbol, color: color, parentID: parent)
            }
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditor(title: "Edit folder", folder: folder, folders: store.folders) { name, symbol, color, parent in
                store.updateFolder(folder, name: name, symbol: symbol, color: color, parentID: parent)
            }
        }
        .sheet(isPresented: $showingRecipeFilters) {
            RecipeFilterEditor(rules: filterEditorRules, folders: store.folders) { value in
                favoritesOnly = value.favoritesOnly; advancedRules = value; advancedRules.favoritesOnly = false
            }
        }
        .sheet(item: $editingSmartCollection) { collection in
            RecipeSmartCollectionEditor(store: store, collection: collection, onSaved: openCollection)
        }
        .sheet(isPresented: $showingBatchEditor) {
            RecipeBatchEditor(store: store, ids: selectedRecipeIDs, onApplied: { selectedRecipeIDs.removeAll(); selectingRecipes = false })
        }
        .alert("Remove smart collection?", isPresented: Binding(get: { smartCollectionToRemove != nil }, set: { if !$0 { smartCollectionToRemove = nil } }), presenting: smartCollectionToRemove) { collection in
            Button("Remove collection", role: .destructive) { store.removeCollection(collection.id); smartCollectionToRemove = nil }
            Button("Cancel", role: .cancel) { smartCollectionToRemove = nil }
        } message: { _ in Text("This removes the saved filter. Recipes remain in your cookbook.") }
        .onChange(of: store.smartCollections) { previous, current in
            if let id = activeSmartCollectionID, let old = previous.first(where: { $0.id == id }), currentRules.equivalent(to: old.rules),
               let updated = current.first(where: { $0.id == id }) { openCollection(updated) }
            if let id = activeSmartCollectionID, !current.contains(where: { $0.id == id }) { activeSmartCollectionID = nil }
        }
        .fileExporter(isPresented: $showingLibraryExport, document: libraryDocument, contentType: .json, defaultFilename: "CookOut Cookbook") { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingLibraryImport, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 100_000_000 else { throw RecipeLibraryError.invalidArchive }
                if store.importLibrary(try Data(contentsOf: url)) { destination = .recipes; selectedFolder = .all }
            } catch { store.errorMessage = error.localizedDescription }
        }
        .alert("Library needs attention", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
            Button("Reload library") { store.reload() }
        } message: { Text(store.errorMessage ?? "") }
        .alert("Remove folder?", isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } }), presenting: folderToRemove) { folder in
            Button("Remove folder", role: .destructive) { store.deleteFolder(folder); folderToRemove = nil }
            Button("Cancel", role: .cancel) { folderToRemove = nil }
        } message: { _ in Text("Recipes and subfolders move to the parent folder. No recipes are deleted.") }
        .onChange(of: destination) { _, value in
            if value == .favorites {
                favoritesOnly = value == .favorites
                selectedFolder = .all
                selectedTags.removeAll()
                query = ""; advancedRules = RecipeCollectionRules(); activeSmartCollectionID = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reload() }
        }
#if os(macOS)
        .frame(minWidth: 900, minHeight: 680)
#endif
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "leaf").font(.system(size: 32, weight: .ultraLight)).foregroundStyle(palette.accent)
                Text("CookOut").font(CookOutTypography.display(36, relativeTo: .largeTitle))
                Text("YOUR KITCHEN, COLLECTED.").font(.caption2.weight(.medium)).tracking(1.4).foregroundStyle(.secondary)
            }.padding(26).padding(.top, 12)
            List(selection: $destination) {
                Section("Cookbook") {
                    Button { destination = .recipes; favoritesOnly = false; clearFilters() } label: {
                        Label("All recipes", systemImage: "book.closed").padding(.vertical, 8)
                    }.buttonStyle(.plain)
                    Button { browse(.unfiled) } label: { Label("Unfiled", systemImage: "tray").padding(.vertical, 8) }
                        .buttonStyle(.plain)
                    sidebarLink(.favorites)
                    sidebarLink(.collections)
                    sidebarLink(.organization)
                }
                if !store.smartCollections.isEmpty {
                    Section("Smart collections") {
                        ForEach(store.smartCollections) { collection in
                            Button { openCollection(collection) } label: {
                                HStack { Label(collection.name, systemImage: "rectangle.stack"); Spacer(); Text("\(collection.rules.filter(store.notes, folders: store.folders).count)").font(.caption).foregroundStyle(.secondary) }
                            }.buttonStyle(.plain).padding(.vertical, 5)
                                .listRowBackground(currentCollection?.id == collection.id && destination == .recipes ? palette.accent.opacity(0.15) : .clear)
                                .contextMenu {
                                    Button("Edit collection") { editingSmartCollection = collection }
                                    Button("Remove collection", role: .destructive) { smartCollectionToRemove = collection }
                                }
                        }
                    }
                }
                Section {
                    OutlineGroup(RecipeFolders.tree(in: store.folders), children: \.children) { node in
                        Button { openFolder(node.id) } label: {
                            HStack {
                                Image(systemName: node.folder.symbol).foregroundStyle(node.folder.color.tint)
                                Text(node.folder.name).lineLimit(1)
                                Spacer(minLength: 2)
                                Text("\(store.count(in: node.id, includingSubfolders: true))").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selectedFolder == .folder(node.id) && destination == .recipes ? palette.accent.opacity(0.15) : Color.clear)
                        .contextMenu { folderMenu(node.folder) }
                        .dropDestination(for: String.self) { (values: [String], _: CGPoint) -> Bool in dropRecipes(values, into: node.id) }
                        .accessibilityAddTraits(selectedFolder == .folder(node.id) ? .isSelected : [])
                    }
                } header: {
                    HStack {
                        Text("Recipe folders")
                        Spacer()
                        Button { showingNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
                            .buttonStyle(.borderless).accessibilityLabel("New recipe folder")
                    }
                }
                Section("In the kitchen") {
                    sidebarLink(.planner)
                    sidebarLink(.bank)
                    sidebarLink(.tools)
                    sidebarLink(.assistant)
                }
                Section("Preferences") { sidebarLink(.appearance) }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Label("\(store.notes.count) recipes to make your own", systemImage: "book.closed")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }
        .background(CookOutTheme.surface(for: colorScheme))
        .navigationTitle("CookOut")
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
    }

    private func sidebarLink(_ value: CookOutDestination) -> some View {
        NavigationLink(value: value) {
            Label {
                Text(value.rawValue).foregroundStyle(.primary)
            } icon: {
                Image(systemName: value.symbol).foregroundStyle(palette.accent)
            }
            .font(.body).padding(.vertical, 8)
        }
    }

    private var library: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if selectedFolder == .all && currentCollection == nil { CockpitHeader(notes: store.notes) }
                    QuickActions(newRecipe: createRecipe, importNote: { showingNotesImport = true }, openAI: { destination = .assistant }, resumeCooking: resumeCooking,
                                 surpriseMe: surpriseMe, canCook: store.notes.contains { !$0.steps.isEmpty || !$0.ingredients.isEmpty })
                    folderBrowser
                    if selectingRecipes {
                        HStack {
                            Text("\(selectedRecipeIDs.count) selected").font(.subheadline)
                            Button("Select all") { selectedRecipeIDs = Set(filteredNotes.map(\.id)) }
                            Menu("Move to folder", systemImage: "folder") {
                                Button("Unfiled") { moveSelected(to: nil) }
                                ForEach(store.folders) { folder in
                                    Button(RecipeFolders.path(for: folder.id, in: store.folders)) { moveSelected(to: folder.id) }
                                }
                            }.disabled(selectedRecipeIDs.isEmpty)
                            Button("Organize selected", systemImage: "tag") { showingBatchEditor = true }.disabled(selectedRecipeIDs.isEmpty)
                            Spacer()
                            Button("Done") { selectingRecipes = false; selectedRecipeIDs.removeAll() }
                        }.buttonStyle(.bordered)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(resultsTitle).font(CookOutTypography.display(28, relativeTo: .title2))
                            Text("\(filteredNotes.count) \(filteredNotes.count == 1 ? "recipe" : "recipes") · \(sort.rawValue.lowercased())\(initialFolderID == nil ? "" : " · includes subfolders")").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if favoritesOnly {
                            Button { favoritesOnly = false } label: { Label("Favorites", systemImage: "heart.fill") }
                                .buttonStyle(.bordered).tint(CookOutTheme.coral)
                        }
                        Button(selectingRecipes ? "Cancel selection" : "Select", systemImage: "checkmark.circle") {
                            selectingRecipes.toggle(); selectedRecipeIDs.removeAll()
                        }.buttonStyle(.bordered)
                        Button { usesGrid.toggle() } label: { Image(systemName: usesGrid ? "rectangle.grid.1x2" : "square.grid.2x2") }
                            .buttonStyle(.bordered).accessibilityLabel(usesGrid ? "Use list layout" : "Use grid layout")
                    }

                    if filteredNotes.isEmpty {
                        CockpitEmptyState(hasRecipes: !store.notes.isEmpty, create: createRecipe, clearFilters: clearFilters)
                    } else if usesGrid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 20)], spacing: 20) {
                            ForEach(filteredNotes) { note in recipeButton(note) }
                        }
                    } else {
                        LazyVStack(spacing: 12) { ForEach(filteredNotes) { note in recipeButton(note) } }
                    }
                }
                .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 32)
                .frame(maxWidth: 1240)
                .frame(maxWidth: .infinity)
                .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: selectedFolder)
                .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: selectedTags)
                .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: favoritesOnly)
                .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: sort)
                .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: usesGrid)
            }
            .background { CockpitBackground(palette: palette, colorScheme: colorScheme) }
            .navigationTitle(favoritesOnly ? "Favorites" : "Recipe library")
            .safeAreaInset(edge: .top, spacing: 0) { librarySearchControls }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Toggle("Favorites only", isOn: $favoritesOnly)
                        Divider()
                        Picker("Sort", selection: $sort) { ForEach(NoteSort.allCases) { Text($0.rawValue).tag($0) } }
                        Divider()
                        Button("Organization tools", systemImage: "tray.full") { destination = .organization }
                        Button("Save smart collection", systemImage: "rectangle.stack.badge.plus") { saveCurrentCollection() }
                        Button("Manage folders", systemImage: "folder") { destination = .collections }
                        Button("Import from Apple Notes", systemImage: "note.text.badge.plus") { showingNotesImport = true }
                        Button("Import cookbook backup", systemImage: "square.and.arrow.down") { showingLibraryImport = true }
                        Button("Export cookbook backup", systemImage: "square.and.arrow.up") { exportCookbook() }
                    } label: { Label("Library controls", systemImage: "slider.horizontal.3") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Recipe", systemImage: "plus") { createRecipe() }
                        Button("New folder", systemImage: "folder.badge.plus") { showingNewFolder = true }
                        Button("Import from Apple Notes", systemImage: "note.text.badge.plus") { showingNotesImport = true }
                    } label: { Label("Add recipe", systemImage: "plus") }
                }
            }
            .sheet(item: $editorPresentation) { presentation in
                NoteEditor(note: presentation.note, folders: store.folders, initialFolderID: presentation.folderID, availableTags: allTags, onSave: store.saveRecipe)
            }
            .sheet(item: $cookingNote) { note in CookingModeView(note: note) { store.markCooked(note) } }
            .sheet(isPresented: $showingNotesImport) { AppleNotesImportView(folders: store.folders, onImport: store.saveRecipe) }
            .onChange(of: store.folders) { _, folders in
                if case .folder(let id) = selectedFolder, !folders.contains(where: { $0.id == id }) { selectedFolder = .all }
            }
            .onChange(of: store.notes) { _, notes in selectedRecipeIDs.formIntersection(Set(notes.map(\.id))) }
        }
        .tint(palette.accent)
        .foregroundStyle(colorScheme == .dark ? Color.primary : CookOutTheme.ink)
#if os(macOS)
        .frame(minWidth: 620, minHeight: 640)
#endif
    }

    private var librarySearchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { searchIsFocused = true } label: {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("Focus recipe search")
                TextField("Search recipes, ingredients, tags, or folders", text: $query)
                    .textFieldStyle(.plain).focused($searchIsFocused).submitLabel(.search)
                    .accessibilityLabel("Search recipes across folders")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
                Button(advancedRules.isActive ? "Filters · on" : "Filters", systemImage: "line.3.horizontal.decrease") { showingRecipeFilters = true }.buttonStyle(.bordered).fixedSize()
                Menu {
                    Picker("Search scope", selection: $searchAllFolders) {
                        Text("All folders").tag(true)
                        Text("Current folder & subfolders").tag(false)
                    }
                } label: {
                    Label(searchAllFolders ? "All folders" : "This folder", systemImage: "folder")
                        .font(.caption.weight(.medium))
                }.fixedSize().accessibilityLabel("Search scope")
            }
            .padding(13)
            .background(palette.background(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(CookOutTheme.border(for: colorScheme)) }

            HStack(alignment: .firstTextBaseline) {
                Label("Tags", systemImage: "tag").font(.caption.weight(.semibold))
                Text(allTags.isEmpty ? "Add tags when editing a recipe to find it across folders." :
                     selectedTags.count > 1 ? "Matching all selected tags" : "Find a recipe across folders")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Save collection", systemImage: "rectangle.stack.badge.plus") { saveCurrentCollection() }.font(.caption).buttonStyle(.borderless)
                if hasSearchFilters {
                    Button("Clear filters") { query = ""; selectedTags.removeAll(); advancedRules = RecipeCollectionRules(); activeSmartCollectionID = nil }
                        .font(.caption).buttonStyle(.borderless)
                }
            }
            if !allTags.isEmpty || !selectedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All tags", symbol: "tag", isSelected: selectedTags.isEmpty) { selectedTags.removeAll() }
                        ForEach(RecipeTags.normalized(allTags + selectedTags.sorted()), id: \.self) { tag in
                            FilterChip(title: tag, symbol: selectedTags.contains(tag) ? "checkmark" : "number", isSelected: selectedTags.contains(tag)) {
                                if !selectedTags.insert(tag).inserted { selectedTags.remove(tag) }
                            }
                        }
                    }
                }
            }
            if hasSearchFilters {
                Text(searchAllFolders ? "Searching every folder\(favoritesOnly ? " · favorites only" : "")" : "Searching \(activeFolderName.lowercased())")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(CookOutTheme.surface(for: colorScheme))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private func recipeButton(_ note: CookingNote) -> some View {
        Group {
            if usesGrid {
                RecipeCard(note: note, folder: store.folders.first(where: { $0.id == note.folderID }), folders: store.folders,
                           onOpen: { openRecipe(note) }, onCook: { cookingNote = note },
                           onPerfected: { store.markPerfected(note) }, onCooked: { store.markCooked(note) },
                           onMove: { store.move(note, to: $0) })
            } else {
                RecipeFileRow(note: note, path: note.folderID.map { RecipeFolders.path(for: $0, in: store.folders) } ?? "Unfiled",
                              open: { openRecipe(note) })
            }
        }
        .overlay(alignment: .topTrailing) {
            if selectingRecipes {
                Button { toggleSelection(note.id) } label: {
                    Image(systemName: selectedRecipeIDs.contains(note.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title2).padding(10).background(.regularMaterial, in: Circle())
                }.buttonStyle(.plain).padding(6).accessibilityLabel("Select \(note.title)")
            }
        }
        .contextMenu { recipeMenu(note) }
        .draggable(note.id.uuidString)
    }

    private var folderBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Recipe library", systemImage: "house") { browse(.all) }
                    if let id = initialFolderID {
                        ForEach(RecipeFolders.ancestors(of: id, in: store.folders)) { folder in
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            Button(folder.name) { openFolder(folder.id) }
                        }
                    } else if selectedFolder == .unfiled { Text("/ Unfiled").foregroundStyle(.secondary) }
                }.buttonStyle(.borderless)
            }
            if !hasSearchFilters && currentCollection == nil && selectedFolder != .unfiled && !favoritesOnly {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(RecipeFolders.children(of: initialFolderID, in: store.folders)) { folder in
                        Button { openFolder(folder.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: folder.symbol).font(.title2).foregroundStyle(folder.color.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(folder.name).font(.headline).lineLimit(1)
                                    Text("\(store.count(in: folder.id, includingSubfolders: true)) recipes · \(RecipeFolders.children(of: folder.id, in: store.folders).count) folders")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(CookOutTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
                                .overlay { RoundedRectangle(cornerRadius: 12).stroke(CookOutTheme.border(for: colorScheme)) }
                        }.buttonStyle(CookOutPressStyle())
                            .contextMenu { folderMenu(folder) }
                            .dropDestination(for: String.self) { (values: [String], _: CGPoint) -> Bool in dropRecipes(values, into: folder.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func folderMenu(_ folder: RecipeFolder) -> some View {
        Button("Open folder", systemImage: "folder") { openFolder(folder.id) }
        Button("Rename or move", systemImage: "pencil") { editingFolder = folder }
        Button("New subfolder", systemImage: "folder.badge.plus") { openFolder(folder.id); showingNewFolder = true }
        Button("Remove folder", systemImage: "trash", role: .destructive) { folderToRemove = folder }
    }

    private func browse(_ scope: RecipeFolderScope) {
        destination = .recipes; favoritesOnly = false; selectedFolder = scope
        query = ""; selectedTags.removeAll(); advancedRules = RecipeCollectionRules(); activeSmartCollectionID = nil; selectingRecipes = false; selectedRecipeIDs.removeAll()
    }
    private var filterEditorRules: RecipeCollectionRules { var copy = advancedRules; copy.favoritesOnly = favoritesOnly; return copy }
    private func saveCurrentCollection() { editingSmartCollection = RecipeSmartCollection(name: "", rules: currentRules) }
    private func openCollection(_ collection: RecipeSmartCollection) { openRules(collection.rules, collection.name); activeSmartCollectionID = collection.id }
    private func openRules(_ rules: RecipeCollectionRules, _ name: String?) {
        destination = .recipes; query = rules.query; selectedTags = Set(rules.tags); favoritesOnly = rules.favoritesOnly
        selectedFolder = rules.unfiledOnly ? .unfiled : rules.folderID.map { .folder($0) } ?? .all
        searchAllFolders = false
        advancedRules = rules; advancedRules.query = ""; advancedRules.tags = []; advancedRules.folderID = nil; advancedRules.unfiledOnly = false; advancedRules.favoritesOnly = false
        selectingRecipes = false; selectedRecipeIDs.removeAll()
        activeSmartCollectionID = name.flatMap { value in store.smartCollections.first { $0.name == value && $0.rules.equivalent(to: rules) }?.id }
    }
    private func openFolder(_ id: UUID) { browse(.folder(id)) }
    private func openRecipe(_ note: CookingNote) { if selectingRecipes { toggleSelection(note.id) } else { edit(note) } }
    private func toggleSelection(_ id: UUID) {
        if !selectedRecipeIDs.insert(id).inserted { selectedRecipeIDs.remove(id) }
    }
    private func moveSelected(to id: UUID?) {
        if store.moveRecipes(selectedRecipeIDs, to: id) { selectedRecipeIDs.removeAll(); selectingRecipes = false }
    }
    private func dropRecipes(_ values: [String], into id: UUID) -> Bool {
        let ids = Set(values.compactMap(UUID.init(uuidString:)))
        guard !ids.isEmpty, ids.count == values.count, ids.isSubset(of: Set(store.notes.map(\.id))) else { return false }
        return store.moveRecipes(ids, to: id)
    }
    private func exportCookbook() {
        do { libraryDocument = RecipeLibraryDocument(data: try store.exportLibrary()); showingLibraryExport = true }
        catch { store.errorMessage = error.localizedDescription }
    }

    @ViewBuilder private func recipeMenu(_ note: CookingNote) -> some View {
        Button("Edit", systemImage: "pencil") { edit(note) }
        if !note.steps.isEmpty || !note.ingredients.isEmpty { Button("Start cooking", systemImage: "play.fill") { cookingNote = note } }
        Button(note.isFavorite ? "Remove Favorite" : "Favorite", systemImage: note.isFavorite ? "heart.slash" : "heart") { store.toggleFavorite(note) }
        Button(note.isPinned ? "Unpin" : "Pin", systemImage: "pin") { store.togglePin(note) }
        Button(note.status == .perfected ? "Recipe Perfected" : "Mark Perfected", systemImage: "checkmark.seal") { store.markPerfected(note) }
            .disabled(note.status == .perfected)
        Button("Cooked +1", systemImage: "flame") { store.markCooked(note) }
        Menu("Move to folder", systemImage: "folder") {
            Button("Unfiled", systemImage: "tray") { store.move(note, to: nil) }
            ForEach(store.folders) { folder in Button(RecipeFolders.path(for: folder.id, in: store.folders), systemImage: folder.symbol) { store.move(note, to: folder.id) } }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(note) }
        ShareLink(item: shareText(for: note)) { Label("Share", systemImage: "square.and.arrow.up") }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { store.delete(note) }
    }

    private func createRecipe() { editorPresentation = RecipeEditorPresentation(note: nil, folderID: initialFolderID) }
    private func edit(_ note: CookingNote) { editorPresentation = RecipeEditorPresentation(note: note, folderID: note.folderID) }
    private func resumeCooking() {
        let cookable = store.notes.filter { !$0.steps.isEmpty || !$0.ingredients.isEmpty }
        cookingNote = cookable.max { ($0.lastCookedAt ?? $0.updatedAt) < ($1.lastCookedAt ?? $1.updatedAt) }
    }
    private func surpriseMe() {
        let cookable = filteredNotes.filter { !$0.steps.isEmpty || !$0.ingredients.isEmpty }
        cookingNote = cookable.randomElement() ?? store.notes.filter { !$0.steps.isEmpty || !$0.ingredients.isEmpty }.randomElement()
    }
    private func clearFilters() { query = ""; selectedTags.removeAll(); selectedFolder = .all; searchAllFolders = true; favoritesOnly = false; advancedRules = RecipeCollectionRules(); activeSmartCollectionID = nil }
    private func shareText(for note: CookingNote) -> String {
        let ingredients = note.ingredients.isEmpty ? "" : "\n\nIngredients\n" + note.ingredients.map { "• \($0)" }.joined(separator: "\n")
        let steps = note.steps.isEmpty ? "" : "\n\nDirections\n" + note.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let tags = note.tags.isEmpty ? "" : "\n\nTags: " + note.tags.joined(separator: ", ")
        return "\(note.title)\n\n\(note.body)\(ingredients)\(steps)\(tags)"
    }
}

private struct CockpitBackground: View {
    let palette: AppPalette; let colorScheme: ColorScheme
    var body: some View {
        ZStack {
            palette.background(for: colorScheme)
            palette.ambientGradient(for: colorScheme)
        }.ignoresSafeArea()
    }
}

private struct CockpitHeader: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let notes: [CookingNote]
    private var favorites: Int { notes.filter(\.isFavorite).count }
    private var perfected: Int { notes.filter { $0.status == .perfected }.count }
    private var cooked: Int { notes.reduce(0) { $0 + $1.cookCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: notes.isEmpty ? 28 : 18) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("THE PERSONAL COOKBOOK")
                        .font(.caption.weight(.semibold)).tracking(2.8).foregroundStyle(palette.accent)
                    Text(notes.isEmpty ? "Good food,\nkept close." : "Recipes worth keeping.")
                        .font(CookOutTypography.display(notes.isEmpty ? 52 : 36, relativeTo: .largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(notes.isEmpty ? "A place for the recipes you love, and the ones you’ll make your own." : "Your favorites, your experiments, your everyday table.")
                        .font(.body).foregroundStyle(.secondary).frame(maxWidth: 490, alignment: .leading)
                }
                Spacer(minLength: 0)
                if horizontalSizeClass != .compact {
                    Image(systemName: "leaf")
                    .font(.system(size: notes.isEmpty ? 52 : 34, weight: .ultraLight))
                    .foregroundStyle(palette.accent)
                    .frame(width: notes.isEmpty ? 106 : 72, height: notes.isEmpty ? 138 : 90)
                    .background(palette.accent.opacity(0.06), in: Capsule())
                    .overlay { Capsule().stroke(CookOutTheme.border(for: colorScheme)) }
                        .accessibilityHidden(true)
                }
            }
            Divider().overlay(CookOutTheme.border(for: colorScheme))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 16) {
                StatTile(value: "\(notes.count)", label: "Recipes", symbol: "book.closed", color: palette.accent)
                StatTile(value: "\(favorites)", label: "Favorites", symbol: "heart", color: CookOutTheme.coral)
                StatTile(value: "\(perfected)", label: "Perfected", symbol: "checkmark.seal", color: CookOutTheme.mint)
                StatTile(value: "\(cooked)", label: "Times cooked", symbol: "flame", color: CookOutTheme.orange)
            }
        }
        .padding(.vertical, notes.isEmpty ? 16 : 8)
    }
}

private struct StatTile: View {
    let value: String; let label: String; let symbol: String; let color: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.body).foregroundStyle(color)
            Text(value).font(CookOutTypography.display(26, relativeTo: .title2)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickActions: View {
    let newRecipe: () -> Void; let importNote: () -> Void; let openAI: () -> Void; let resumeCooking: () -> Void; let surpriseMe: () -> Void; let canCook: Bool
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { actions; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 12) { actions }
        }.controlSize(.large)
    }
    @ViewBuilder private var actions: some View {
        Button("New recipe", systemImage: "plus", action: newRecipe).buttonStyle(.borderedProminent)
        Button("Import a note", systemImage: "square.and.arrow.down", action: importNote).buttonStyle(.bordered)
        Menu {
            Button("Resume cooking", systemImage: "play", action: resumeCooking)
            Button("Surprise me", systemImage: "shuffle", action: surpriseMe)
        } label: { Label("Cook something", systemImage: "fork.knife") }
            .disabled(!canCook).buttonStyle(.bordered)
        Button("Ask CookAssistant", systemImage: "sparkles", action: openAI).buttonStyle(.borderless)
    }
}

private struct RecipeFileRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let note: CookingNote
    let path: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                Image(systemName: "doc.text").font(.title2).foregroundStyle(note.mealType.tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title.isEmpty ? "Untitled recipe" : note.title).font(.headline).foregroundStyle(.primary)
                    Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 48)
                if note.isFavorite { Image(systemName: "heart.fill").foregroundStyle(CookOutTheme.coral) }
                if note.totalMinutes > 0 { Text("\(note.totalMinutes) min").font(.caption).foregroundStyle(.secondary) }
                Text(note.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(CookOutTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(CookOutTheme.border(for: colorScheme)) }
        }.buttonStyle(CookOutPressStyle())
    }
}

private struct FilterChip: View {
    @Environment(\.cookOutPalette) private var palette
    let title: String; let symbol: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium))
                .padding(.horizontal, 13).padding(.vertical, 9)
                .foregroundStyle(isSelected ? palette.accent : .secondary)
                .background(palette.accent.opacity(isSelected ? 0.12 : 0.035), in: Capsule())
                .overlay { Capsule().stroke(palette.accent.opacity(isSelected ? 0.35 : 0.12)) }
        }.buttonStyle(CookOutPressStyle()).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RecipeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    let note: CookingNote
    let folder: RecipeFolder?
    let folders: [RecipeFolder]
    let onOpen: () -> Void
    let onCook: () -> Void
    let onPerfected: () -> Void
    let onCooked: () -> Void
    let onMove: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label(note.mealType.rawValue.uppercased(), systemImage: note.mealType.symbol)
                            .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(note.mealType.tint)
                        Spacer(minLength: 8)
                        if note.isPinned { Image(systemName: "pin.fill").foregroundStyle(CookOutTheme.orange).accessibilityLabel("Pinned") }
                        if note.isFavorite { Image(systemName: "heart.fill").foregroundStyle(CookOutTheme.coral).accessibilityLabel("Favorite") }
                    }
                    Text(note.title.isEmpty ? "Untitled recipe" : note.title)
                        .font(CookOutTypography.display(27, relativeTo: .title2)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(note.body.isEmpty ? "A new favorite in the making. Add your notes and make it yours." : note.body)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    ViewThatFits(in: .horizontal) {
                        recipeMetadata.font(.caption)
                        recipeMetadata.font(.caption2)
                    }
                    HStack(spacing: 6) {
                        ForEach(note.tags.prefix(2), id: \.self) { tag in
                            Text(tag).font(.caption).lineLimit(1).padding(.horizontal, 9).padding(.vertical, 5)
                                .background(note.mealType.tint.opacity(0.075), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        Text(note.status.rawValue).font(.caption).foregroundStyle(note.status == .perfected ? CookOutTheme.mint : .secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CookOutPressStyle())
            .accessibilityLabel("Edit \(note.title.isEmpty ? "untitled recipe" : note.title)")

            Divider().padding(.horizontal, 24)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { cardActions }
                VStack(alignment: .leading, spacing: 10) { cardActions }
            }
            .font(.caption).padding(.horizontal, 20).padding(.top, 14)

            HStack {
                if let folder {
                    Label(RecipeFolders.path(for: folder.id, in: folders), systemImage: folder.symbol).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Menu {
                    Button(note.status == .perfected ? "Perfected" : "Mark perfected", systemImage: "checkmark.seal") { onPerfected() }
                        .disabled(note.status == .perfected)
                    Divider()
                    Menu("Move to folder", systemImage: "folder") {
                        Button("Unfiled", systemImage: "tray") { onMove(nil) }
                        ForEach(folders) { destination in
                            Button(RecipeFolders.path(for: destination.id, in: folders), systemImage: destination.symbol) { onMove(destination.id) }
                        }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24) }
                    .accessibilityLabel("Actions for \(note.title.isEmpty ? "untitled recipe" : note.title)")
            }.padding(.horizontal, 20).padding(.vertical, 14)

        }
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
        .background(CookOutTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(CookOutTheme.border(for: colorScheme)) }
        .shadow(color: CookOutTheme.ink.opacity(isHovered ? 0.10 : 0.035), radius: isHovered ? 18 : 8, y: isHovered ? 8 : 3)
        .offset(y: isHovered && !reduceMotion ? -3 : 0)
        .onHover { isHovered = $0 }
        .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: isHovered)
        .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: note.cookCount)
    }

    private var recipeMetadata: some View {
        HStack(spacing: 14) {
            if note.totalMinutes > 0 { Label("\(note.totalMinutes) min", systemImage: "clock") }
            Label("\(note.servings) servings", systemImage: "person.2")
            Spacer(minLength: 0)
            if note.rating > 0 { Label("\(note.rating)", systemImage: "star.fill").foregroundStyle(CookOutTheme.mango) }
        }.foregroundStyle(.secondary)
    }

    @ViewBuilder private var cardActions: some View {
        if !note.steps.isEmpty || !note.ingredients.isEmpty {
            Button("Cook", systemImage: "play", action: onCook).buttonStyle(.borderedProminent)
        }
        Button(action: onCooked) { Label("Cooked \(note.cookCount) · +1", systemImage: "flame") }
            .buttonStyle(.bordered).tint(CookOutTheme.orange)
            .accessibilityLabel("Log another cook, cooked \(note.cookCount) times")
            .help("Add one to this recipe’s cooked count")
    }
}

private struct CockpitEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    let hasRecipes: Bool; let create: () -> Void; let clearFilters: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: hasRecipes ? "line.3.horizontal.decrease" : "book.closed")
                .font(.system(size: 32, weight: .light)).foregroundStyle(CookOutTheme.olive)
            Text(hasRecipes ? "Nothing here just yet" : "Every recipe has a story.")
                .font(CookOutTypography.display(30, relativeTo: .title))
            Text(hasRecipes ? "Clear your filters or explore another collection." : "Start with a family favorite, a weeknight staple, or something entirely new.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            HStack {
                if hasRecipes { Button("Clear filters", systemImage: "xmark", action: clearFilters).buttonStyle(.bordered) }
                Button("New recipe", systemImage: "plus", action: create).buttonStyle(.borderedProminent)
            }.controlSize(.large)
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 54)
        .background(CookOutTheme.surface(for: colorScheme).opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(CookOutTheme.border(for: colorScheme)) }
    }
}

#Preview { ContentView() }
