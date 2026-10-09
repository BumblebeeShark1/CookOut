import Foundation
import Combine

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [CookingNote] = []
    @Published private(set) var folders: [RecipeFolder] = []
    @Published private(set) var smartCollections: [RecipeSmartCollection] = []
    @Published private(set) var isAvailable = true
    @Published var errorMessage: String?
    private let directory: URL
    private let fileURL: URL
    private let writeData: (Data, URL) throws -> Void
    private var hasSavedLibrary = false

    init(directory: URL? = nil, writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CookOut", isDirectory: true)
        fileURL = self.directory.appendingPathComponent("library.json")
        self.writeData = writeData
        reload()
    }

    func reload() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let exists = FileManager.default.fileExists(atPath: fileURL.path)
            hasSavedLibrary = exists
            var library: RecipeLibraryArchive
            if exists {
                let data = try Data(contentsOf: fileURL)
                guard data.count <= 100_000_000 else { throw RecipeLibraryError.invalidArchive }
                library = try JSONDecoder().decode(RecipeLibraryArchive.self, from: data)
            } else {
                // Leave the legacy files intact as a recovery copy. Migration only
                // publishes a single atomic document containing recipes and folders.
                let oldNotes: [CookingNote] = try readLegacy("notes.json", fallback: [])
                let oldFolders: [RecipeFolder] = try readLegacy("folders.json", fallback: [])
                library = RecipeLibraryArchive(notes: oldNotes, folders: oldFolders)
                library.folders = addingStarterFolders(to: library.folders)
            }
            try library.validate()
            library = library.reconciled()
            isAvailable = true
            publish(library)
            errorMessage = nil
            if !exists { _ = commit(library) }
        } catch {
            isAvailable = false
            errorMessage = "\(RecipeLibraryError.unavailable.localizedDescription)\n\(error.localizedDescription)"
        }
    }

    func save(_ note: CookingNote) {
        _ = saveRecipe(note)
    }

    @discardableResult func saveRecipe(_ note: CookingNote) -> Bool {
        mutate { library in
            var updated = note
            updated.updatedAt = .now
            if let folderID = updated.folderID, !library.folders.contains(where: { $0.id == folderID }) { updated.folderID = nil }
            if let index = library.notes.firstIndex(where: { $0.id == note.id }) { library.notes[index] = updated }
            else { library.notes.append(updated) }
        }
    }

    func delete(_ note: CookingNote) { mutate { $0.notes.removeAll { $0.id == note.id } } }

    func duplicate(_ note: CookingNote) {
        var copy = note
        copy.id = UUID()
        copy.title = note.title.isEmpty ? "Copy" : "\(note.title) Copy"
        copy.isPinned = false
        save(copy)
    }

    func togglePin(_ note: CookingNote) { update(note.id) { $0.isPinned.toggle() } }
    func toggleFavorite(_ note: CookingNote) { update(note.id) { $0.isFavorite.toggle() } }
    func markCooked(_ note: CookingNote) { update(note.id) { $0.cookCount += 1; $0.lastCookedAt = .now } }
    func markPerfected(_ note: CookingNote) { update(note.id) { $0.status = .perfected } }

    @discardableResult func createFolder(name: String, symbol: String, color: FolderColor, parentID: UUID? = nil) -> Bool {
        mutate { library in
            let clean = try checkedName(name, parentID: parentID, excluding: nil, in: library.folders)
            library.folders.append(RecipeFolder(name: clean, symbol: symbol, color: color, parentID: parentID))
        }
    }

    @discardableResult func updateFolder(_ folder: RecipeFolder, name: String, symbol: String, color: FolderColor, parentID: UUID? = nil) -> Bool {
        mutate { library in
            guard let index = library.folders.firstIndex(where: { $0.id == folder.id }) else { throw RecipeLibraryError.invalidFolder }
            if let parentID, RecipeFolders.descendants(of: folder.id, in: library.folders).contains(parentID) { throw RecipeLibraryError.invalidFolder }
            if let parentID {
                let subtreeDepth = RecipeFolders.descendants(of: folder.id, in: library.folders).map {
                    RecipeFolders.ancestors(of: $0, in: library.folders).count - RecipeFolders.ancestors(of: folder.id, in: library.folders).count + 1
                }.max() ?? 1
                guard RecipeFolders.ancestors(of: parentID, in: library.folders).count + subtreeDepth <= 64 else { throw RecipeLibraryError.invalidFolder }
            }
            let clean = try checkedName(name, parentID: parentID, excluding: folder.id, in: library.folders)
            library.folders[index].name = clean
            library.folders[index].symbol = symbol
            library.folders[index].color = color
            library.folders[index].parentID = parentID
        }
    }

    /// Removing a folder promotes its children and recipes to its parent;
    /// no recipe content is deleted, and both updates are saved together.
    func deleteFolder(_ folder: RecipeFolder) {
        mutate { library in
            guard let current = library.folders.first(where: { $0.id == folder.id }) else { return }
            library.folders.removeAll { $0.id == folder.id }
            for index in library.folders.indices where library.folders[index].parentID == folder.id {
                library.folders[index].parentID = current.parentID
            }
            for index in library.notes.indices where library.notes[index].folderID == folder.id {
                library.notes[index].folderID = current.parentID
                library.notes[index].updatedAt = .now
            }
        }
    }

    func move(_ note: CookingNote, to folderID: UUID?) { moveRecipes([note.id], to: folderID) }

    @discardableResult func moveRecipes(_ ids: Set<UUID>, to folderID: UUID?) -> Bool {
        mutate { library in
            if let folderID, !library.folders.contains(where: { $0.id == folderID }) { throw RecipeLibraryError.invalidFolder }
            for index in library.notes.indices where ids.contains(library.notes[index].id) {
                library.notes[index].folderID = folderID
                library.notes[index].updatedAt = .now
            }
        }
    }

    @discardableResult func setRecipes(_ ids: Set<UUID>, in folderID: UUID, originallyInFolder originalIDs: Set<UUID>) -> Bool {
        mutate { library in
            guard library.folders.contains(where: { $0.id == folderID }) else { throw RecipeLibraryError.invalidFolder }
            for index in library.notes.indices {
                let note = library.notes[index]
                if ids.contains(note.id), !originalIDs.contains(note.id) {
                    library.notes[index].folderID = folderID
                    library.notes[index].updatedAt = .now
                } else if originalIDs.contains(note.id), !ids.contains(note.id), note.folderID == folderID {
                    library.notes[index].folderID = nil
                    library.notes[index].updatedAt = .now
                }
            }
        }
    }

    func count(in folderID: UUID?, includingSubfolders: Bool = false) -> Int {
        guard let folderID else { return notes.filter { $0.folderID == nil }.count }
        let ids = includingSubfolders ? RecipeFolders.descendants(of: folderID, in: folders) : [folderID]
        return notes.filter { $0.folderID.map(ids.contains) ?? false }.count
    }

    func addStarterFolders() { mutate { $0.folders = addingStarterFolders(to: $0.folders) } }

    func exportLibrary() throws -> Data {
        guard isAvailable else { throw RecipeLibraryError.unavailable }
        var library = RecipeLibraryArchive(notes: notes, folders: folders, smartCollections: smartCollections)
        if hasSavedLibrary {
            let data = try Data(contentsOf: fileURL)
            guard data.count <= 100_000_000 else { throw RecipeLibraryError.invalidArchive }
            library = try JSONDecoder().decode(RecipeLibraryArchive.self, from: data)
        }
        try library.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(library.reconciled())
    }

    /// Import adds a separate tree, remapping every ID so an imported cookbook
    /// can never overwrite an existing recipe or steal an existing folder.
    @discardableResult func importLibrary(_ data: Data) -> Bool {
        do {
            guard data.count <= 100_000_000 else { throw RecipeLibraryError.invalidArchive }
            let imported = try JSONDecoder().decode(RecipeLibraryArchive.self, from: data)
            try imported.validate()
            let safe = imported.reconciled()
            return mutate { library in
                let root = RecipeFolder(name: "Imported cookbook", symbol: "square.and.arrow.down", color: .cyan)
                let mapping = Dictionary(uniqueKeysWithValues: safe.folders.map { ($0.id, UUID()) })
                library.folders.append(root)
                library.folders += safe.folders.map { folder in
                    var copy = folder
                    copy.id = mapping[folder.id]!
                    copy.parentID = folder.parentID.flatMap { mapping[$0] } ?? root.id
                    return copy
                }
                for imported in safe.smartCollections ?? [] {
                    var copy = imported; copy.id = UUID()
                    if let folder = copy.rules.folderID { copy.rules.folderID = mapping[folder] ?? UUID() }
                    let base = String(copy.name.prefix(60))
                    var name = base; var suffix = 2
                    while (library.smartCollections ?? []).contains(where: { RecipeTags.key($0.name) == RecipeTags.key(name) }) {
                        name = "\(base) (\(suffix))"; suffix += 1
                    }
                    copy.name = name
                    library.smartCollections = (library.smartCollections ?? []) + [copy]
                }
                library.notes += safe.notes.map { note in
                    var copy = note
                    copy.id = UUID()
                    copy.folderID = note.folderID.flatMap { mapping[$0] } ?? root.id
                    return copy
                }
            }
        } catch { errorMessage = error.localizedDescription; return false }
    }

    @discardableResult func saveCollection(_ collection: RecipeSmartCollection) -> Bool {
        mutate { library in
            var copy = collection
            copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.rules.tags = RecipeTags.normalized(copy.rules.tags)
            try copy.validate()
            var collections = library.smartCollections ?? []
            guard !collections.contains(where: { $0.id != copy.id && RecipeTags.key($0.name) == RecipeTags.key(copy.name) }) else { throw RecipeOrganizationError.duplicateName }
            if let index = collections.firstIndex(where: { $0.id == copy.id }) { collections[index] = copy }
            else { collections.append(copy) }
            library.smartCollections = collections
        }
    }

    @discardableResult func removeCollection(_ id: UUID) -> Bool {
        mutate { $0.smartCollections?.removeAll { $0.id == id } }
    }

    @discardableResult func organizeRecipes(_ ids: Set<UUID>, changes: RecipeBatchChanges) -> Bool {
        mutate { library in
            try changes.validate()
            guard !ids.isEmpty, ids.isSubset(of: Set(library.notes.map(\.id))),
                  !changes.changeFolder || changes.folderID == nil || library.folders.contains(where: { $0.id == changes.folderID }) else { throw RecipeOrganizationError.invalidSelection }
            for index in library.notes.indices where ids.contains(library.notes[index].id) {
                let copy = changes.applying(to: library.notes[index])
                if copy != library.notes[index] { library.notes[index] = copy; library.notes[index].updatedAt = .now }
            }
        }
    }

    /// Rename merges matching spellings and updates saved tag-based collections
    /// together with recipe tags, so collections keep their meaning.
    @discardableResult func renameTag(_ tag: String, to replacement: String) -> Bool {
        mutate { library in
            let newTags = RecipeTags.normalized([replacement])
            guard RecipeTags.parse(replacement).count == 1, let newTag = newTags.first, newTag.count <= 100, !RecipeTags.normalized([tag]).isEmpty else { throw RecipeOrganizationError.invalidRules }
            let oldKey = RecipeTags.key(RecipeTags.normalized([tag])[0])
            for index in library.notes.indices {
                guard RecipeTags.normalized(library.notes[index].tags).contains(where: { RecipeTags.key($0) == oldKey }) else { continue }
                library.notes[index].tags = RecipeTags.normalized(RecipeTags.normalized(library.notes[index].tags).map { RecipeTags.key($0) == oldKey ? newTag : $0 })
                library.notes[index].updatedAt = .now
            }
            if var collections = library.smartCollections {
                for index in collections.indices { collections[index].rules.tags = RecipeTags.normalized(collections[index].rules.tags.map { RecipeTags.key($0) == oldKey ? newTag : $0 }) }
                library.smartCollections = collections
            }
        }
    }

    /// Add a bank selection in one write. Existing IDs are skipped, preserving
    /// edited copies of source recipes and concurrent saves from other windows.
    @discardableResult func addRecipes(_ recipes: [CookingNote], to folderID: UUID?, tags: [String] = []) -> Bool {
        mutate { library in
            guard (1...250).contains(recipes.count), Set(recipes.map(\.id)).count == recipes.count,
                  folderID == nil || library.folders.contains(where: { $0.id == folderID }),
                  tags.count <= 50, tags.allSatisfy({ !RecipeTags.normalized([$0]).isEmpty && $0.count <= 100 }) else { throw RecipeOrganizationError.invalidSelection }
            let existing = Set(library.notes.map(\.id))
            library.notes += recipes.filter { !existing.contains($0.id) }.map { note in
                var copy = note; copy.folderID = folderID
                copy.tags = RecipeTags.normalized(note.tags + tags); copy.updatedAt = .now
                return copy
            }
        }
    }

    @discardableResult func fileSuggestedRecipe(_ original: CookingNote, to folderID: UUID) -> Bool {
        mutate { library in
            guard let index = library.notes.firstIndex(where: { $0.id == original.id }), library.notes[index] == original,
                  library.notes[index].folderID == nil else { throw RecipeOrganizationError.staleReview }
            guard library.folders.contains(where: { $0.id == folderID }) else { throw RecipeOrganizationError.invalidSelection }
            library.notes[index].folderID = folderID; library.notes[index].updatedAt = .now
        }
    }

    private func checkedName(_ name: String, parentID: UUID?, excluding id: UUID?, in folders: [RecipeFolder]) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 200 else { throw RecipeLibraryError.invalidArchive }
        if let parentID, !folders.contains(where: { $0.id == parentID }) { throw RecipeLibraryError.invalidFolder }
        if let parentID, RecipeFolders.ancestors(of: parentID, in: folders).count >= 64 { throw RecipeLibraryError.invalidFolder }
        guard !folders.contains(where: { $0.id != id && $0.parentID == parentID && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) else {
            throw RecipeLibraryError.duplicateName
        }
        return clean
    }

    private func addingStarterFolders(to existing: [RecipeFolder]) -> [RecipeFolder] {
        var result = existing
        let starters = RecipeFolders.starterFolders()
        for root in starters where root.parentID == nil {
            guard !existing.contains(where: { $0.parentID == nil && $0.name.localizedCaseInsensitiveCompare(root.name) == .orderedSame }) else { continue }
            let ids = RecipeFolders.descendants(of: root.id, in: starters)
            result += starters.filter { ids.contains($0.id) }
        }
        return result
    }

    private func readLegacy<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return fallback }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func update(_ id: UUID, change: (inout CookingNote) -> Void) {
        mutate { library in
            guard let index = library.notes.firstIndex(where: { $0.id == id }) else { return }
            change(&library.notes[index])
            library.notes[index].updatedAt = .now
        }
    }

    @discardableResult private func mutate(_ change: (inout RecipeLibraryArchive) throws -> Void) -> Bool {
        guard isAvailable else { errorMessage = RecipeLibraryError.unavailable.localizedDescription; return false }
        var library = RecipeLibraryArchive(notes: notes, folders: folders, smartCollections: smartCollections)
        do {
            // Separate app windows share this file. Start each edit from the
            // latest committed state rather than a window's older snapshot.
            if hasSavedLibrary {
                do {
                    let data = try Data(contentsOf: fileURL)
                    guard data.count <= 100_000_000 else { throw RecipeLibraryError.invalidArchive }
                    library = try JSONDecoder().decode(RecipeLibraryArchive.self, from: data)
                    try library.validate()
                    library = library.reconciled()
                } catch {
                    isAvailable = false
                    throw RecipeLibraryError.unavailable
                }
            }
            try change(&library)
            return commit(library)
        } catch { errorMessage = error.localizedDescription; return false }
    }

    @discardableResult private func commit(_ library: RecipeLibraryArchive) -> Bool {
        do {
            try library.validate()
            let library = library.reconciled()
            let data = try JSONEncoder().encode(library)
            try writeData(data, fileURL)
            hasSavedLibrary = true
            publish(library)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Your changes could not be saved. Your saved recipes are unchanged.\n\(error.localizedDescription)"
            return false
        }
    }

    private func publish(_ library: RecipeLibraryArchive) {
        notes = library.notes.sorted { $0.isPinned != $1.isPinned ? $0.isPinned : $0.updatedAt > $1.updatedAt }
        smartCollections = (library.smartCollections ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        folders = library.folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
