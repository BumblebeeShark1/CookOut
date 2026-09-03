import SwiftUI

private enum FolderScope: Hashable { case all, unfiled, folder(UUID) }

struct ContentView: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private enum NoteSort: String, CaseIterable, Identifiable {
        case updated = "Recently edited", title = "Title", rating = "Highest rated", cooked = "Most cooked", quickest = "Quickest"
        var id: Self { self }
    }

    @StateObject private var store = NotesStore()
    @State private var query = ""
    @State private var selectedNote: CookingNote?
    @State private var showingEditor = false
    @State private var selectedTag: String?
    @State private var selectedFolder: FolderScope = .all
    @State private var sort: NoteSort = .updated
    @State private var favoritesOnly = false
    @State private var cookingNote: CookingNote?
    @State private var showingChat = false
    @State private var showingAppearance = false
    @State private var showingFolders = false
    @State private var showingNotesImport = false
    @AppStorage("cookout.libraryGrid") private var usesGrid = true

    private var allTags: [String] {
        Array(Set(store.notes.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredNotes: [CookingNote] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = store.notes.filter { note in
            let matchesFolder: Bool
            switch selectedFolder {
            case .all: matchesFolder = true
            case .unfiled: matchesFolder = note.folderID == nil
            case .folder(let id): matchesFolder = note.folderID == id
            }
            let matchesTag = selectedTag == nil || note.tags.contains { $0.caseInsensitiveCompare(selectedTag!) == .orderedSame }
            let matchesFavorite = !favoritesOnly || note.isFavorite
            let matchesSearch = search.isEmpty || note.title.localizedCaseInsensitiveContains(search) ||
                note.body.localizedCaseInsensitiveContains(search) || note.ingredients.joined(separator: " ").localizedCaseInsensitiveContains(search) ||
                note.tags.joined(separator: " ").localizedCaseInsensitiveContains(search)
            return matchesFolder && matchesTag && matchesFavorite && matchesSearch
        }
        return filtered.sorted { first, second in
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

    private var activeFolderName: String {
        switch selectedFolder {
        case .all: "All Recipes"
        case .unfiled: "Unfiled"
        case .folder(let id): store.folders.first(where: { $0.id == id })?.name ?? "All Recipes"
        }
    }

    private var initialFolderID: UUID? {
        if case .folder(let id) = selectedFolder { return id }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CockpitHeader(notes: store.notes, folderCount: store.folders.count)
                    QuickActions(newRecipe: createRecipe, importNote: { showingNotesImport = true }, openAI: { showingChat = true }, resumeCooking: resumeCooking,
                                 surpriseMe: surpriseMe, canCook: store.notes.contains { !$0.steps.isEmpty || !$0.ingredients.isEmpty })
                    FolderRail(folders: store.folders, notes: store.notes, selected: $selectedFolder, manage: { showingFolders = true })

                    if !allTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(title: "All tags", symbol: "tag", isSelected: selectedTag == nil) { selectedTag = nil }
                                ForEach(allTags, id: \.self) { tag in
                                    FilterChip(title: tag, symbol: "number", isSelected: selectedTag == tag) { selectedTag = tag }
                                }
                            }
                        }
                    }

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activeFolderName).font(.title2.bold())
                            Text("\(filteredNotes.count) visible · \(sort.rawValue.lowercased())").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if favoritesOnly {
                            Button { favoritesOnly = false } label: { Label("Favorites", systemImage: "heart.fill") }
                                .buttonStyle(.bordered).tint(CookOutTheme.coral)
                        }
                        Button { usesGrid.toggle() } label: { Image(systemName: usesGrid ? "rectangle.grid.1x2" : "square.grid.2x2") }
                            .buttonStyle(.bordered).accessibilityLabel(usesGrid ? "Use list layout" : "Use grid layout")
                    }

                    if filteredNotes.isEmpty {
                        CockpitEmptyState(hasRecipes: !store.notes.isEmpty, create: createRecipe, clearFilters: clearFilters)
                    } else if usesGrid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                            ForEach(filteredNotes) { note in recipeButton(note) }
                        }
                    } else {
                        LazyVStack(spacing: 12) { ForEach(filteredNotes) { note in recipeButton(note) } }
                    }
                }
                .padding(.horizontal).padding(.top, 12).padding(.bottom, 96)
            }
            .background { CockpitBackground(palette: palette, colorScheme: colorScheme) }
            .navigationTitle("Chef’s Cockpit")
            .searchable(text: $query, prompt: "Search recipes, ingredients, and tags")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button { showingAppearance = true } label: { Label("Appearance", systemImage: "paintpalette.fill") }
                }
                ToolbarItem {
                    Menu {
                        Toggle("Favorites only", isOn: $favoritesOnly)
                        Divider()
                        Picker("Sort", selection: $sort) { ForEach(NoteSort.allCases) { Text($0.rawValue).tag($0) } }
                        Divider()
                        Button("Manage folders", systemImage: "folder") { showingFolders = true }
                        Button("Import from Apple Notes", systemImage: "note.text.badge.plus") { showingNotesImport = true }
                    } label: { Label("Cockpit controls", systemImage: "slider.horizontal.3") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Recipe", systemImage: "plus") { createRecipe() }
                        Button("Import from Apple Notes", systemImage: "note.text.badge.plus") { showingNotesImport = true }
                    } label: { Label("Add recipe", systemImage: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                CockpitCommandDock(newRecipe: createRecipe, openAI: { showingChat = true }, folders: { showingFolders = true })
            }
            .sheet(isPresented: $showingEditor, onDismiss: { selectedNote = nil }) {
                NoteEditor(note: selectedNote, folders: store.folders, initialFolderID: initialFolderID, onSave: store.save)
            }
            .sheet(item: $cookingNote) { note in CookingModeView(note: note) { store.markCooked(note) } }
            .sheet(isPresented: $showingChat) { CookingChatView(cookbook: store.notes, folders: store.folders, onSaveRecipe: store.save) }
            .sheet(isPresented: $showingAppearance) { AppearanceSettingsView() }
            .sheet(isPresented: $showingFolders) { FolderManagerView(store: store) }
            .sheet(isPresented: $showingNotesImport) { AppleNotesImportView(folders: store.folders, onImport: store.save) }
            .onChange(of: store.folders) { _, folders in
                if case .folder(let id) = selectedFolder, !folders.contains(where: { $0.id == id }) { selectedFolder = .all }
            }
        }.tint(palette.accent)
    }

    @ViewBuilder private func recipeButton(_ note: CookingNote) -> some View {
        RecipeCard(
            note: note,
            folder: store.folders.first(where: { $0.id == note.folderID }),
            folders: store.folders,
            onOpen: { edit(note) },
            onPerfected: { store.markPerfected(note) },
            onCooked: { store.markCooked(note) },
            onMove: { store.move(note, to: $0) }
        )
            .contextMenu { recipeMenu(note) }
    }

    @ViewBuilder private func recipeMenu(_ note: CookingNote) -> some View {
        Button("Edit", systemImage: "pencil") { edit(note) }
        if !note.steps.isEmpty || !note.ingredients.isEmpty { Button("Start cooking", systemImage: "play.fill") { cookingNote = note } }
        Button(note.isFavorite ? "Remove Favorite" : "Favorite", systemImage: note.isFavorite ? "heart.slash" : "heart") { store.toggleFavorite(note) }
        Button(note.isPinned ? "Unpin" : "Pin", systemImage: "pin") { store.togglePin(note) }
        Button(note.status == .perfected ? "Recipe Perfected" : "Mark Perfected", systemImage: "checkmark.seal") { store.markPerfected(note) }
            .disabled(note.status == .perfected)
        Button("Cooked +1", systemImage: "flame") { store.markCooked(note) }
        Menu("Move to Folder", systemImage: "folder") {
            Button("Unfiled", systemImage: "tray") { store.move(note, to: nil) }
            ForEach(store.folders) { folder in Button(folder.name, systemImage: folder.symbol) { store.move(note, to: folder.id) } }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(note) }
        ShareLink(item: shareText(for: note)) { Label("Share", systemImage: "square.and.arrow.up") }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { store.delete(note) }
    }

    private func createRecipe() { selectedNote = nil; showingEditor = true }
    private func edit(_ note: CookingNote) { selectedNote = note; showingEditor = true }
    private func resumeCooking() {
        let cookable = store.notes.filter { !$0.steps.isEmpty || !$0.ingredients.isEmpty }
        cookingNote = cookable.max { ($0.lastCookedAt ?? $0.updatedAt) < ($1.lastCookedAt ?? $1.updatedAt) }
    }
    private func surpriseMe() {
        let cookable = filteredNotes.filter { !$0.steps.isEmpty || !$0.ingredients.isEmpty }
        cookingNote = cookable.randomElement() ?? store.notes.filter { !$0.steps.isEmpty || !$0.ingredients.isEmpty }.randomElement()
    }
    private func clearFilters() { query = ""; selectedTag = nil; selectedFolder = .all; favoritesOnly = false }
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
            palette.background(for: colorScheme); palette.ambientGradient(for: colorScheme)
            RadialGradient(colors: [Color.cyan.opacity(colorScheme == .dark ? 0.018 : 0.025), .clear], center: .topTrailing, startRadius: 10, endRadius: 520)
        }.ignoresSafeArea()
    }
}

private struct CockpitHeader: View {
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    let notes: [CookingNote]; let folderCount: Int
    private var favorites: Int { notes.filter(\.isFavorite).count }
    private var perfected: Int { notes.filter { $0.status == .perfected }.count }
    private var cooked: Int { notes.reduce(0) { $0 + $1.cookCount } }
    private var plannedMinutes: Int { notes.reduce(0) { $0 + $1.totalMinutes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("KITCHEN COMMAND CENTER", systemImage: "dial.high.fill").font(.caption2.bold()).tracking(1.4).foregroundStyle(palette.accent)
                    Text("Everything mise en place.").font(.title2.bold())
                    Text("Plan, refine, cook, and ask your AI sous-chef from one focused workspace.").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Label("Systems Ready", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(CookOutTheme.mint)
                    Text("\(folderCount) folders · \(plannedMinutes) planned min").font(.caption2).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                StatTile(value: "\(notes.count)", label: "Recipes", symbol: "book.closed.fill", color: CookOutTheme.orange)
                StatTile(value: "\(favorites)", label: "Favorites", symbol: "heart.fill", color: CookOutTheme.coral)
                StatTile(value: "\(perfected)", label: "Perfected", symbol: "checkmark.seal.fill", color: CookOutTheme.mint)
                StatTile(value: "\(cooked)", label: "Times cooked", symbol: "flame.fill", color: CookOutTheme.berry)
            }
        }
        .padding(18)
        .background(colorScheme == .dark ? CookOutTheme.grapheneRaised.opacity(0.86) : Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(colorScheme == .dark ? 0.09 : 0.5)) }
        .overlay(alignment: .top) { Capsule().fill(palette.gradient).frame(height: 4).padding(.horizontal, 22) }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 22, y: 10)
    }
}

private struct StatTile: View {
    let value: String; let label: String; let symbol: String; let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 30, height: 30).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) { Text(value).font(.title3.bold().monospacedDigit()); Text(label).font(.caption2).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct QuickActions: View {
    let newRecipe: () -> Void; let importNote: () -> Void; let openAI: () -> Void; let resumeCooking: () -> Void; let surpriseMe: () -> Void; let canCook: Bool
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
            CockpitAction(title: "New Recipe", subtitle: "Open a fresh station", symbol: "plus", color: CookOutTheme.coral, action: newRecipe)
            CockpitAction(title: "Import Apple Note", subtitle: "CookAssistant organizes it", symbol: "note.text.badge.plus", color: CookOutTheme.orange, action: importNote)
            CockpitAction(title: "CookAssistant", subtitle: "Ask, plan, or edit", symbol: "sparkles", color: CookOutTheme.berry, action: openAI)
            CockpitAction(title: "Resume Cooking", subtitle: "Return to the line", symbol: "play.fill", color: CookOutTheme.mint, disabled: !canCook, action: resumeCooking)
            CockpitAction(title: "Surprise Me", subtitle: "Pick from the pass", symbol: "dice.fill", color: .cyan, disabled: !canCook, action: surpriseMe)
        }
    }
}

private struct CockpitAction: View {
    let title: String; let subtitle: String; let symbol: String; let color: Color; var disabled = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.headline).foregroundStyle(.white).frame(width: 36, height: 36).background(color.gradient, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.bold()).foregroundStyle(.primary); Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength: 0)
            }.padding(12).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.45 : 1)
    }
}

private struct FolderRail: View {
    let folders: [RecipeFolder]; let notes: [CookingNote]; @Binding var selected: FolderScope; let manage: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Label("Kitchen Stations", systemImage: "folder.fill").font(.headline); Spacer(); Button("Manage", systemImage: "gearshape", action: manage).font(.caption.bold()) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FolderChip(title: "All Recipes", count: notes.count, symbol: "square.grid.2x2.fill", color: CookOutTheme.orange, selected: selected == .all) { selected = .all }
                    FolderChip(title: "Unfiled", count: notes.filter { $0.folderID == nil }.count, symbol: "tray.fill", color: .secondary, selected: selected == .unfiled) { selected = .unfiled }
                    ForEach(folders) { folder in
                        FolderChip(title: folder.name, count: notes.filter { $0.folderID == folder.id }.count, symbol: folder.symbol, color: folder.color.tint, selected: selected == .folder(folder.id)) { selected = .folder(folder.id) }
                    }
                    Button(action: manage) { VStack(spacing: 6) { Image(systemName: "folder.badge.plus").font(.title3); Text("New Folder").font(.caption.bold()) }.frame(minWidth: 92, minHeight: 64) }.buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct FolderChip: View {
    let title: String; let count: Int; let symbol: String; let color: Color; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).foregroundStyle(color).font(.headline)
                VStack(alignment: .leading, spacing: 1) { Text(title).font(.subheadline.bold()).lineLimit(1); Text("\(count) recipes").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.horizontal, 13).frame(minHeight: 64).background(selected ? color.opacity(0.16) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(selected ? color.opacity(0.8) : .clear, lineWidth: 1.5) }
        }.buttonStyle(.plain)
    }
}

private struct FilterChip: View {
    let title: String; let symbol: String; let isSelected: Bool; let action: () -> Void
    var body: some View { Button(action: action) { Label(title, systemImage: symbol).font(.caption.bold()) }.buttonStyle(.borderedProminent).tint(isSelected ? CookOutTheme.orange : .secondary.opacity(0.32)) }
}

private struct RecipeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let note: CookingNote
    let folder: RecipeFolder?
    let folders: [RecipeFolder]
    let onOpen: () -> Void
    let onPerfected: () -> Void
    let onCooked: () -> Void
    let onMove: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .top) {
                        Image(systemName: note.mealType.symbol).font(.title3).foregroundStyle(.white).frame(width: 46, height: 46).background(note.mealType.tint.gradient, in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.isEmpty ? "Untitled recipe" : note.title).font(.title3.bold()).lineLimit(2)
                            HStack(spacing: 6) {
                                Text(note.status.rawValue.uppercased()).font(.footnote.bold()).foregroundStyle(note.status == .perfected ? CookOutTheme.mint : .secondary)
                                if let folder { Label(folder.name, systemImage: folder.symbol).foregroundStyle(folder.color.tint) }
                            }.font(.footnote).lineLimit(1)
                        }
                        Spacer()
                        if note.isPinned { Image(systemName: "pin.fill").foregroundStyle(CookOutTheme.orange) }
                        if note.isFavorite { Image(systemName: "heart.fill").foregroundStyle(CookOutTheme.coral) }
                    }
                    Text(note.body.isEmpty ? "No briefing yet. Open the recipe to add notes." : note.body).font(.body).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 13) {
                        if note.totalMinutes > 0 { Label("\(note.totalMinutes)m", systemImage: "clock.fill") }
                        Label("\(note.servings)", systemImage: "person.2.fill")
                        Label("\(note.ingredients.count)", systemImage: "basket.fill")
                        Label("\(note.steps.count)", systemImage: "list.number")
                        Spacer()
                        if note.rating > 0 { Label("\(note.rating)", systemImage: "star.fill").foregroundStyle(CookOutTheme.mango) }
                    }.font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        ForEach(note.tags.prefix(3), id: \.self) { tag in
                            Text(tag).font(.footnote.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(note.mealType.tint.opacity(0.12), in: Capsule())
                        }
                        Spacer()
                        Text(note.updatedAt, format: .dateTime.month(.abbreviated).day()).font(.footnote).foregroundStyle(.tertiary)
                    }
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(note.title.isEmpty ? "untitled recipe" : note.title)")

            Divider().padding(.horizontal, 14)
            HStack(spacing: 8) {
                Button(action: onPerfected) {
                    Label(note.status == .perfected ? "Perfected" : "Mark Perfected", systemImage: note.status == .perfected ? "checkmark.seal.fill" : "checkmark.seal")
                }
                .buttonStyle(.bordered)
                .tint(CookOutTheme.mint)
                .disabled(note.status == .perfected)

                Button(action: onCooked) {
                    Label("Cooked \(note.cookCount)", systemImage: "flame.fill")
                }
                .buttonStyle(.bordered)
                .tint(CookOutTheme.berry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Unfiled", systemImage: "tray") { onMove(nil) }
                ForEach(folders) { destination in
                    Button(destination.name, systemImage: destination.symbol) { onMove(destination.id) }
                }
            } label: {
                Label(folder?.name ?? "Add to Folder", systemImage: folder?.symbol ?? "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(folder?.color.tint ?? .secondary)
            .accessibilityLabel(folder == nil ? "Add recipe to folder" : "Move recipe from \(folder!.name)")
            .font(.subheadline.weight(.semibold))
            .padding(12)
        }
            .frame(maxWidth: .infinity, minHeight: 244, alignment: .topLeading)
            .background(colorScheme == .dark ? CookOutTheme.grapheneRaised.opacity(0.9) : Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .top) { Capsule().fill(note.mealType.tint).frame(width: 72, height: 3).padding(.top, 1) }
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.08)) }.shadow(color: note.mealType.tint.opacity(0.08), radius: 14, y: 7)
    }
}

private struct CockpitEmptyState: View {
    let hasRecipes: Bool; let create: () -> Void; let clearFilters: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: hasRecipes ? "line.3.horizontal.decrease.circle" : "fork.knife.circle.fill").font(.system(size: 42)).foregroundStyle(CookOutTheme.orange)
            Text(hasRecipes ? "No recipes on this station" : "Your cockpit is ready").font(.title3.bold())
            Text(hasRecipes ? "Clear the active filters or choose another folder." : "Create your first recipe, then organize it into a kitchen station.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack { if hasRecipes { Button("Clear Filters", systemImage: "xmark", action: clearFilters).buttonStyle(.bordered) }; Button("New Recipe", systemImage: "plus", action: create).buttonStyle(.borderedProminent) }
        }.frame(maxWidth: .infinity).padding(.vertical, 56).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CockpitCommandDock: View {
    @Environment(\.cookOutPalette) private var palette
    let newRecipe: () -> Void; let openAI: () -> Void; let folders: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: folders) { Label("Stations", systemImage: "folder.fill") }.buttonStyle(.bordered)
            Button(action: openAI) { Label("CookAssistant", systemImage: "sparkles").fontWeight(.semibold).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(palette.accent)
            Button(action: newRecipe) { Label("New", systemImage: "plus") }.buttonStyle(.bordered)
        }.padding(.horizontal).padding(.vertical, 10).background(.ultraThinMaterial).overlay(alignment: .top) { Rectangle().fill(palette.gradient).frame(height: 2) }
    }
}

#Preview { ContentView() }
