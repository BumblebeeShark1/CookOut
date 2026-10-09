import SwiftUI

struct FolderManagerView: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cookOutPalette) private var palette
    @ObservedObject var store: NotesStore
    var onOpenFolder: ((UUID) -> Void)?
    @State private var currentFolderID: UUID?
    @State private var editingFolder: RecipeFolder?
    @State private var showingNewFolder = false
    @State private var folderToDelete: RecipeFolder?
    @State private var addingRecipesToFolder: RecipeFolder?

    private var childFolders: [RecipeFolder] { RecipeFolders.children(of: currentFolderID, in: store.folders) }

    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Your recipe filesystem", title: "A home for every recipe.",
                                  subtitle: "Organize bread, sauces, desserts, entrées, and cuisines in folders within folders.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Button("Folders", systemImage: "folder") { currentFolderID = nil }
                        if let id = currentFolderID {
                            ForEach(RecipeFolders.ancestors(of: id, in: store.folders)) { folder in
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                Button(folder.name) { currentFolderID = folder.id }
                            }
                        }
                    }.buttonStyle(.borderless)
                }
                HStack {
                    Text("\(childFolders.count) folders").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let id = currentFolderID, let onOpenFolder {
                        Button("Browse recipes", systemImage: "book.closed") { onOpenFolder(id) }
                    }
                    Button("New folder", systemImage: "folder.badge.plus") { showingNewFolder = true }
                        .buttonStyle(.borderedProminent)
                }
                if childFolders.isEmpty {
                    CookOutPanel(title: "") {
                        CookOutEmptyState(symbol: "folder", title: "Room for a new folder.",
                                          message: "Create subfolders here, or browse the recipes in this folder.")
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 22)], spacing: 22) {
                        ForEach(childFolders) { folder in
                            CookOutPanel(title: "") {
                                HStack {
                                    Button { currentFolderID = folder.id } label: {
                                        Label(folder.name, systemImage: folder.symbol)
                                            .font(CookOutTypography.display(25, relativeTo: .title2))
                                            .foregroundStyle(folder.color.tint).frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).accessibilityLabel("Open folder \(folder.name)")
                                    Menu {
                                        if let onOpenFolder { Button("Browse recipes", systemImage: "book.closed") { onOpenFolder(folder.id) } }
                                        Button("Rename or move", systemImage: "pencil") { editingFolder = folder }
                                        Button("Remove folder", systemImage: "trash", role: .destructive) { folderToDelete = folder }
                                    } label: { Image(systemName: "ellipsis").frame(width: 30, height: 30) }
                                        .accessibilityLabel("Options for \(folder.name)")
                                }
                                Text("\(store.count(in: folder.id, includingSubfolders: true)) recipes · \(RecipeFolders.children(of: folder.id, in: store.folders).count) subfolders")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Divider()
                                HStack {
                                    Button("Choose recipes", systemImage: "plus") { addingRecipesToFolder = folder }
                                    Spacer()
                                    Button("Open", systemImage: "arrow.right") { currentFolderID = folder.id }
                                }.buttonStyle(.borderless).font(.subheadline)
                            }
                        }
                    }
                }
                Button("Add starter categories", systemImage: "folder.badge.plus") { store.addStarterFolders() }
                    .buttonStyle(.borderless).help("Add any missing top-level recipe categories without changing existing folders.")
                Label("Removing a folder keeps its recipes and subfolders in the parent folder.", systemImage: "heart")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Folders")
            .toolbar {
                if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            }
            .sheet(isPresented: $showingNewFolder) {
                FolderEditor(title: "New folder", folders: store.folders, initialParentID: currentFolderID) { name, symbol, color, parent in
                    store.createFolder(name: name, symbol: symbol, color: color, parentID: parent)
                }
            }
            .sheet(item: $editingFolder) { folder in
                FolderEditor(title: "Edit folder", folder: folder, folders: store.folders) { name, symbol, color, parent in
                    store.updateFolder(folder, name: name, symbol: symbol, color: color, parentID: parent)
                }
            }
            .sheet(item: $addingRecipesToFolder) { folder in FolderRecipePicker(folder: folder, store: store) }
            .onChange(of: store.folders) { _, folders in
                if let id = currentFolderID, !folders.contains(where: { $0.id == id }) { currentFolderID = nil }
            }
            .alert("Remove \(folderToDelete?.name ?? "folder")?",
                   isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
                   presenting: folderToDelete) { folder in
                Button("Remove folder", role: .destructive) { store.deleteFolder(folder); folderToDelete = nil }
                Button("Cancel", role: .cancel) { folderToDelete = nil }
            } message: { _ in Text("Recipes and subfolders move to the parent. Recipes at the top level become Unfiled.") }
        }
        .tint(palette.accent)
        .cookOutFolderManagerFrame()
    }
}

struct FolderEditor: View {
    private static let symbols = [
        "folder.fill", "fork.knife", "heart.fill", "star.fill", "flame.fill", "leaf.fill",
        "carrot.fill", "birthday.cake.fill", "cup.and.saucer.fill", "mug.fill", "wineglass.fill",
        "takeoutbag.and.cup.and.straw.fill", "basket.fill", "cart.fill", "frying.pan.fill", "oven.fill",
        "refrigerator.fill", "fish.fill", "globe.americas.fill", "house.fill", "person.2.fill",
        "figure.2.and.child.holdinghands", "party.popper.fill", "gift.fill", "sun.max.fill", "moon.stars.fill",
        "snowflake", "beach.umbrella.fill", "airplane", "tent.fill", "book.closed.fill", "bookmark.fill",
        "checkmark.seal.fill", "sparkles", "bolt.fill", "clock.fill", "calendar", "shippingbox.fill"
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let onSave: (String, String, FolderColor, UUID?) -> Bool
    let folders: [RecipeFolder]
    let editingID: UUID?
    @State private var parentID: UUID?
    @State private var saveFailed = false
    @State private var name: String
    @State private var symbol: String
    @State private var color: FolderColor

    init(title: String, folder: RecipeFolder? = nil, folders: [RecipeFolder] = [], initialParentID: UUID? = nil, onSave: @escaping (String, String, FolderColor, UUID?) -> Bool) {
        self.title = title
        self.onSave = onSave
        self.folders = folders
        self.editingID = folder?.id
        _parentID = State(initialValue: folder?.parentID ?? initialParentID)
        _name = State(initialValue: folder?.name ?? "")
        _symbol = State(initialValue: folder?.symbol ?? "folder.fill")
        _color = State(initialValue: folder?.color ?? .orange)
    }

    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A place for your recipes", title: title == "New folder" ? "Create a recipe folder." : "Rename or move your folder.", subtitle: "Choose a name, a little symbol, and a color that feels right.")
                CookOutPanel(title: "The name", symbol: "textformat") {
                    TextField("Family favorites", text: $name).font(CookOutTypography.display(28, relativeTo: .title2)).cookOutField()
                }
                CookOutPanel(title: "Location", symbol: "folder") {
                    Picker("Parent folder", selection: $parentID) {
                        Text("Recipe library (top level)").tag(nil as UUID?)
                        ForEach(folders.filter { folder in
                            guard let editingID else { return true }
                            return !RecipeFolders.descendants(of: editingID, in: folders).contains(folder.id)
                        }) { folder in
                            Text(RecipeFolders.path(for: folder.id, in: folders)).tag(Optional(folder.id))
                        }
                    }
                    if saveFailed {
                        Text("Could not save. Use a unique folder name and a valid location, or check library storage access.")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                CookOutPanel(title: "A little character", subtitle: "Choose an icon.", symbol: "square.grid.3x3") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 12)], spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { option in
                            Button { symbol = option } label: {
                                Image(systemName: option).font(.title2.weight(.light)).frame(maxWidth: .infinity).frame(height: 52)
                                    .background(symbol == option ? color.tint.opacity(0.15) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(symbol == option ? color.tint : .clear) }
                            }.buttonStyle(CookOutPressStyle()).foregroundStyle(.primary)
                                .accessibilityLabel(option.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(symbol == option ? .isSelected : [])
                        }
                    }
                }
                CookOutPanel(title: "A touch of color", symbol: "paintpalette") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))], spacing: 14) {
                        ForEach(FolderColor.allCases) { option in
                            Button { color = option } label: {
                                Circle().fill(option.tint).frame(width: 42, height: 42)
                                    .overlay { if color == option { Image(systemName: "checkmark").foregroundStyle(.white).font(.headline) } }
                                    .padding(5).overlay { Circle().stroke(color == option ? option.tint : .clear) }
                            }.buttonStyle(CookOutPressStyle()).accessibilityLabel(option.rawValue)
                                .accessibilityAddTraits(color == option ? .isSelected : [])
                        }
                    }
                }
            }
            .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: symbol)
            .animation(CookOutTheme.motion(reduceMotion: reduceMotion), value: color)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if onSave(name, symbol, color, parentID) { dismiss() } else { saveFailed = true }
                    }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .cookOutSheetFrame(width: 680, height: 720)
    }
}

private struct FolderRecipePicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NotesStore
    let folder: RecipeFolder
    private let originalIDs: Set<UUID>
    @State private var selectedIDs: Set<UUID>
    @State private var saveFailed = false
    @State private var query = ""

    init(folder: RecipeFolder, store: NotesStore) {
        self.folder = folder
        self.store = store
        originalIDs = Set(store.notes.filter { $0.folderID == folder.id }.map(\.id))
        _selectedIDs = State(initialValue: originalIDs)
    }

    private var recipes: [CookingNote] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return store.notes }
        return store.notes.filter {
            $0.title.localizedCaseInsensitiveContains(term) ||
            $0.tags.joined(separator: " ").localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "Curate your collection", title: folder.name, subtitle: "Choose the recipes that belong here. Changes are saved when you’re ready.")
                HStack {
                    Label("\(selectedIDs.count) selected", systemImage: "checkmark.circle").font(.subheadline)
                    Spacer()
                }
                if store.notes.isEmpty {
                    CookOutEmptyState(symbol: "book.closed", title: "Your first recipe is waiting.", message: "Create or import a recipe, then add it to this collection.")
                } else if recipes.isEmpty {
                    CookOutEmptyState(symbol: "magnifyingglass", title: "No matching recipes.", message: "Try another ingredient, tag, or title.")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(recipes) { recipe in
                            Button { toggle(recipe.id) } label: {
                                CookOutPanel(title: "") {
                                    HStack(spacing: 18) {
                                        Image(systemName: selectedIDs.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2).foregroundStyle(selectedIDs.contains(recipe.id) ? folder.color.tint : .secondary)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title)
                                                .font(CookOutTypography.display(23, relativeTo: .title3)).foregroundStyle(.primary)
                                            if let currentFolder = store.folders.first(where: { $0.id == recipe.folderID }), currentFolder.id != folder.id {
                                                Text("In \(RecipeFolders.path(for: currentFolder.id, in: store.folders)) · selecting will move it").font(.caption).foregroundStyle(.secondary)
                                            } else {
                                                Text(recipe.folderID == folder.id ? "In this collection" : "Unfiled").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: recipe.mealType.symbol).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(CookOutPressStyle()).accessibilityAddTraits(selectedIDs.contains(recipe.id) ? .isSelected : [])
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search recipes")
            .navigationTitle("Recipes in \(folder.name)")
            .alert("Recipes could not be moved", isPresented: $saveFailed) { Button("OK", role: .cancel) {} } message: { Text(store.errorMessage ?? "Try again.") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.setRecipes(selectedIDs, in: folder.id, originallyInFolder: originalIDs) { dismiss() }
                        else { saveFailed = true }
                    }.fontWeight(.semibold)
                }
            }
        }
        .tint(folder.color.tint)
        .cookOutFolderPickerFrame()
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }


}

private extension View {
    @ViewBuilder func cookOutFolderManagerFrame() -> some View {
#if os(macOS)
        frame(minWidth: 640, minHeight: 560)
#else
        self
#endif
    }

    @ViewBuilder func cookOutFolderPickerFrame() -> some View {
#if os(macOS)
        frame(minWidth: 680, minHeight: 720)
#else
        self
#endif
    }
}
