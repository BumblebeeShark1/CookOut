import SwiftUI

struct FolderManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cookOutPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: NotesStore
    @State private var editingFolder: RecipeFolder?
    @State private var showingNewFolder = false
    @State private var folderToDelete: RecipeFolder?
    @State private var addingRecipesToFolder: RecipeFolder?

    var body: some View {
        NavigationStack {
            Group {
                if store.folders.isEmpty {
                    ContentUnavailableView("Build your kitchen stations",
                                           systemImage: "folder.badge.plus",
                                           description: Text("Folders keep recipes organized by occasion, cuisine, person, or project."))
                } else {
                    List {
                        Section("Kitchen stations") {
                            ForEach(store.folders) { folder in
                                VStack(alignment: .leading, spacing: 10) {
                                    Button { editingFolder = folder } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: folder.symbol)
                                                .font(.title2).foregroundStyle(folder.color.tint)
                                                .frame(width: 42, height: 42)
                                                .background(folder.color.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(folder.name).foregroundStyle(.primary).font(.title3.bold())
                                                Text("\(store.count(in: folder.id)) recipes").foregroundStyle(.secondary).font(.footnote)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    HStack(spacing: 8) {
                                        Button { addingRecipesToFolder = folder } label: {
                                            Label("Add Existing Recipes", systemImage: "plus.circle.fill")
                                        }
                                        .font(.body.weight(.semibold))
                                        .buttonStyle(.borderedProminent)
                                        .tint(folder.color.tint)

                                        Spacer(minLength: 4)

                                        Button("Edit", systemImage: "pencil") { editingFolder = folder }
                                            .buttonStyle(.bordered)

                                        Button("Delete", systemImage: "trash", role: .destructive) { folderToDelete = folder }
                                            .buttonStyle(.bordered)
                                            .tint(.red)
                                    }
                                }
                                .padding(.vertical, 7)
                                .swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { folderToDelete = folder } }
                                .contextMenu {
                                    Button("Add Existing Recipes", systemImage: "plus.circle") { addingRecipesToFolder = folder }
                                    Button("Edit", systemImage: "pencil") { editingFolder = folder }
                                    Button("Delete", systemImage: "trash", role: .destructive) { folderToDelete = folder }
                                }
                            }
                        }
                        Section {
                            Label("Deleting a folder moves its recipes to Unfiled. Recipes are never deleted with their folder.", systemImage: "shield.checkered")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background { ZStack { palette.background(for: colorScheme); palette.ambientGradient(for: colorScheme) }.ignoresSafeArea() }
            .navigationTitle("Recipe Folders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                }
            }
            .sheet(isPresented: $showingNewFolder) {
                FolderEditor(title: "New Folder") { name, symbol, color in
                    store.createFolder(name: name, symbol: symbol, color: color)
                }
            }
            .sheet(item: $editingFolder) { folder in
                FolderEditor(title: "Edit Folder", folder: folder) { name, symbol, color in
                    store.updateFolder(folder, name: name, symbol: symbol, color: color)
                }
            }
            .sheet(item: $addingRecipesToFolder) { folder in
                FolderRecipePicker(folder: folder, store: store)
            }
            .alert("Delete \(folderToDelete?.name ?? "folder")?",
                   isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
                   presenting: folderToDelete) { folder in
                Button("Delete Folder", role: .destructive) { store.deleteFolder(folder); folderToDelete = nil }
                Button("Cancel", role: .cancel) { folderToDelete = nil }
            } message: { _ in
                Text("Its recipes will move to Unfiled.")
            }
        }
        .tint(palette.accent)
        .cookOutFolderManagerFrame()
    }
}

private struct FolderEditor: View {
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
    let title: String
    let onSave: (String, String, FolderColor) -> Void
    @State private var name: String
    @State private var symbol: String
    @State private var color: FolderColor

    init(title: String, folder: RecipeFolder? = nil, onSave: @escaping (String, String, FolderColor) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: folder?.name ?? "")
        _symbol = State(initialValue: folder?.symbol ?? "folder.fill")
        _color = State(initialValue: folder?.color ?? .orange)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Family favorites", text: $name).font(.body) }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58))], spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { option in
                            Button { symbol = option } label: {
                                Image(systemName: option).font(.title2).frame(width: 50, height: 50)
                                    .background(symbol == option ? color.tint.opacity(0.22) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay { if symbol == option { RoundedRectangle(cornerRadius: 12).stroke(color.tint, lineWidth: 2) } }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 4)
                }
                Section("Color") {
                    HStack {
                        ForEach(FolderColor.allCases) { option in
                            Button { color = option } label: {
                                Circle().fill(option.tint).frame(width: 30, height: 30)
                                    .overlay { if color == option { Circle().stroke(.white, lineWidth: 3).padding(3) } }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(name, symbol, color); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct FolderRecipePicker: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NotesStore
    let folder: RecipeFolder
    @State private var selectedIDs: Set<UUID>
    @State private var query = ""

    init(folder: RecipeFolder, store: NotesStore) {
        self.folder = folder
        self.store = store
        _selectedIDs = State(initialValue: Set(store.notes.filter { $0.folderID == folder.id }.map(\.id)))
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
            Group {
                if store.notes.isEmpty {
                    ContentUnavailableView("No recipes yet", systemImage: "book.closed", description: Text("Create or import a recipe first."))
                } else {
                    List(recipes) { recipe in
                        Button { toggle(recipe.id) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: selectedIDs.contains(recipe.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(selectedIDs.contains(recipe.id) ? folder.color.tint : .secondary)
                                Image(systemName: recipe.mealType.symbol)
                                    .foregroundStyle(recipe.mealType.tint)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title).font(.headline)
                                    if let currentFolder = store.folders.first(where: { $0.id == recipe.folderID }), currentFolder.id != folder.id {
                                        Text("Currently in \(currentFolder.name) · selecting will move it")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    } else if recipe.folderID == folder.id {
                                        Text("In \(folder.name)").font(.footnote).foregroundStyle(folder.color.tint)
                                    } else {
                                        Text("Unfiled").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .searchable(text: $query, prompt: "Search recipes")
                }
            }
            .navigationTitle("Recipes in \(folder.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.fontWeight(.semibold)
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

    private func save() {
        let recipes = store.notes
        for recipe in recipes {
            if selectedIDs.contains(recipe.id), recipe.folderID != folder.id {
                store.move(recipe, to: folder.id)
            } else if !selectedIDs.contains(recipe.id), recipe.folderID == folder.id {
                store.move(recipe, to: nil)
            }
        }
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
        frame(minWidth: 520, minHeight: 560)
#else
        self
#endif
    }
}
