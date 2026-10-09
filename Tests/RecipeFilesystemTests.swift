import Foundation

@main
struct RecipeFilesystemTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            guard condition else { fatalError("FAIL: \(message)") }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CookOut-filesystem-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NotesStore(directory: directory)
        check(store.isAvailable && store.errorMessage == nil, "new library is available")
        check(Set(store.folders.filter { $0.parentID == nil }.map(\.name)).isSuperset(of: ["Bread", "Sauces", "Desserts", "Entrées", "Cuisines"]), "starter categories")
        let starterCount = store.folders.count
        store.addStarterFolders()
        check(store.folders.count == starterCount, "starter categories are idempotent")
        let bread = store.folders.first { $0.name == "Bread" }!
        let sourdough = store.folders.first { $0.name == "Sourdough" }!
        check(sourdough.parentID == bread.id, "nested starter folders")
        check(RecipeFolders.path(for: sourdough.id, in: store.folders) == "Bread / Sourdough", "full paths")
        check(store.createFolder(name: "Experiments", symbol: "flask", color: .mint, parentID: sourdough.id), "create nested folder")
        let experiments = store.folders.first { $0.name == "Experiments" }!
        check(!store.createFolder(name: " experiments ", symbol: "folder", color: .mint, parentID: sourdough.id), "duplicate sibling rejected")
        check(store.createFolder(name: "Experiments", symbol: "folder", color: .mint, parentID: bread.id), "same name in another parent is allowed")
        check(!store.createFolder(name: " ", symbol: "folder", color: .mint), "blank name rejected")
        check(!store.createFolder(name: "Orphan", symbol: "folder", color: .mint, parentID: UUID()), "missing parent rejected")
        check(!store.updateFolder(bread, name: bread.name, symbol: bread.symbol, color: bread.color, parentID: experiments.id), "descendant move rejected")
        check(!store.updateFolder(bread, name: bread.name, symbol: bread.symbol, color: bread.color, parentID: bread.id), "self move rejected")
        var loaf = CookingNote(title: "Country loaf", ingredients: ["Flour", "Water"], folderID: experiments.id)
        loaf.tags = ["Weekend"]
        store.save(loaf)
        let soup = CookingNote(title: "Soup")
        store.save(soup)
        check(store.count(in: bread.id, includingSubfolders: true) == 1, "recursive recipe count")
        check(store.count(in: bread.id) == 0, "direct recipe count")
        check(RecipeLibrarySearch.filter(store.notes, folders: store.folders, query: "Bread Sourdough", tags: [], folderScope: .all, searchAllFolders: true, favoritesOnly: false).map(\.id) == [loaf.id], "search ancestor names")
        check(RecipeLibrarySearch.filter(store.notes, folders: store.folders, query: "", tags: [], folderScope: .folder(bread.id), searchAllFolders: false, favoritesOnly: false).map(\.id) == [loaf.id], "browse includes descendants")
        check(!store.moveRecipes([loaf.id], to: UUID()), "invalid recipe destination rejected")
        check(store.notes.first { $0.id == loaf.id }?.folderID == experiments.id, "failed move preserves folder")
        check(store.updateFolder(experiments, name: "Test loaves", symbol: "oven", color: .mango, parentID: bread.id), "rename and move subtree")
        check(RecipeFolders.path(for: experiments.id, in: store.folders) == "Bread / Test loaves", "updated path")
        check(store.notes.first { $0.id == loaf.id }?.folderID == experiments.id, "move keeps recipe identity")
        check(store.moveRecipes([loaf.id, soup.id], to: sourdough.id), "bulk move")
        check(store.count(in: sourdough.id) == 2, "bulk move all selected recipes")
        let reloaded = NotesStore(directory: directory)
        check(reloaded.notes.count == 2 && reloaded.folders.count == store.folders.count, "restart restores whole library")
        check(reloaded.notes.first { $0.id == loaf.id }?.folderID == sourdough.id, "recipe location survives restart")
        // A second window starts from the latest disk state, preserving another window's edit.
        let newer = CookingNote(title: "Newer window recipe")
        reloaded.save(newer)
        let currentExport = try JSONDecoder().decode(RecipeLibraryArchive.self, from: store.exportLibrary())
        check(currentExport.notes.contains { $0.id == newer.id }, "stale window exports latest saved recipes")
        store.toggleFavorite(loaf)
        let concurrent = NotesStore(directory: directory)
        check(concurrent.notes.contains { $0.id == newer.id }, "stale window does not drop newer recipes")
        check(concurrent.notes.first { $0.id == loaf.id }?.isFavorite == true, "stale window edit is applied")
        let originalIDs = Set(store.notes.filter { $0.folderID == sourdough.id }.map(\.id))
        reloaded.move(soup, to: bread.id)
        check(store.setRecipes([loaf.id], in: sourdough.id, originallyInFolder: originalIDs), "folder picker applies a selection delta")
        check(store.notes.first { $0.id == soup.id }?.folderID == bread.id, "picker does not undo a concurrent move")
        let child = RecipeFolder(name: "Saved child", parentID: sourdough.id)
        check(store.createFolder(name: child.name, symbol: child.symbol, color: child.color, parentID: child.parentID), "child before parent removal")
        let savedChild = store.folders.first { $0.name == child.name }!
        store.deleteFolder(sourdough)
        check(!store.folders.contains { $0.id == sourdough.id }, "folder removed")
        check(store.folders.first { $0.id == savedChild.id }?.parentID == bread.id, "children promoted to parent")
        check(store.notes.first { $0.id == loaf.id }?.folderID == bread.id, "recipes promoted to parent")
        store.deleteFolder(bread)
        check(store.notes.first { $0.id == loaf.id }?.folderID == nil, "root removal unfiles recipes")
        check(store.folders.first { $0.id == savedChild.id }?.parentID == nil, "root removal promotes child to root")
        check(!NotesStore(directory: directory).folders.contains { $0.name == "Bread" }, "deleted category not recreated at restart")
        let data = try store.exportLibrary()
        let archive = try JSONDecoder().decode(RecipeLibraryArchive.self, from: data)
        check(archive.notes.count == store.notes.count, "export all recipes")
        let originalNotes = Set(store.notes.map(\.id))
        let originalFolders = Set(store.folders.map(\.id))
        check(store.importLibrary(data), "import valid cookbook")
        check(store.notes.count == originalNotes.count * 2, "import appends without overwriting")
        check(Set(store.notes.map(\.id)).count == store.notes.count, "import has fresh recipe IDs")
        check(Set(store.folders.map(\.id)).count == originalFolders.count * 2 + 1, "import has separate folder tree")
        let importedRoot = store.folders.first { $0.name == "Imported cookbook" }!
        check(store.folders.filter { !originalFolders.contains($0.id) && $0.id != importedRoot.id }.allSatisfy { $0.parentID != nil }, "imported tree attached to separate root")
        let countBeforeMalformed = store.notes.count
        check(!store.importLibrary(Data("invalid".utf8)), "malformed import rejected")
        var invalid = archive
        invalid.version = 99
        check(!store.importLibrary(try JSONEncoder().encode(invalid)), "unknown archive version rejected")
        invalid = archive
        invalid.notes.append(invalid.notes[0])
        check(!store.importLibrary(try JSONEncoder().encode(invalid)), "duplicate archive recipe IDs rejected")
        invalid = archive
        invalid.folders.append(invalid.folders[0])
        check(!store.importLibrary(try JSONEncoder().encode(invalid)), "duplicate archive folder IDs rejected")
        invalid = archive
        invalid.notes[0].cookCount = Int.max
        check(!store.importLibrary(try JSONEncoder().encode(invalid)), "overflow-prone external values rejected")
        check(store.notes.count == countBeforeMalformed, "invalid imports leave recipes unchanged")
        let oldFolderData = Data("[{\"id\":\"\(UUID())\",\"name\":\"Legacy\",\"symbol\":\"folder\",\"color\":\"orange\",\"createdAt\":0}]".utf8)
        check(try JSONDecoder().decode([RecipeFolder].self, from: oldFolderData)[0].parentID == nil, "legacy folder decodes without parentID")
        var cycleA = RecipeFolder(name: "A")
        var cycleB = RecipeFolder(name: "B", parentID: cycleA.id)
        cycleA.parentID = cycleB.id
        cycleB.parentID = cycleA.id
        let repaired = RecipeFolders.repaired([cycleA, cycleB])
        check(repaired.contains { $0.parentID == nil }, "cyclic graph detached")
        check(!RecipeFolders.tree(in: repaired).isEmpty, "repaired folders navigable")
        let orphan = RecipeFolder(name: "Orphan", parentID: UUID())
        check(RecipeFolders.repaired([orphan])[0].parentID == nil, "orphan parent repaired")
        var orphanNote = CookingNote(title: "Orphan recipe", folderID: UUID())
        let fixed = RecipeLibraryArchive(notes: [orphanNote], folders: [orphan]).reconciled()
        check(fixed.notes[0].folderID == nil, "missing recipe folder unfiles safely")
        var deep: [RecipeFolder] = []
        for n in 0..<100 { deep.append(RecipeFolder(name: "Level \(n)", parentID: deep.last?.id)) }
        let safeDepth = RecipeFolders.repaired(deep)
        check(safeDepth.allSatisfy { RecipeFolders.ancestors(of: $0.id, in: safeDepth).count <= 64 }, "malformed depth bounded")
        check(RecipeFolders.ancestors(of: cycleA.id, in: [cycleA, cycleB]).count == 2, "raw cycle path terminates")
        // Legacy migration preserves recipes, folders, and the original files.
        let legacyDirectory = directory.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyFolder = RecipeFolder(name: "Family favorites")
        orphanNote.folderID = legacyFolder.id
        let legacyNotesData = try JSONEncoder().encode([orphanNote])
        try legacyNotesData.write(to: legacyDirectory.appendingPathComponent("notes.json"))
        try JSONEncoder().encode([legacyFolder]).write(to: legacyDirectory.appendingPathComponent("folders.json"))
        let migrated = NotesStore(directory: legacyDirectory)
        check(migrated.notes.first?.id == orphanNote.id && migrated.notes.first?.folderID == legacyFolder.id, "migration preserves IDs and folder")
        check(migrated.folders.contains { $0.id == legacyFolder.id }, "migration keeps custom categories")
        check(try Data(contentsOf: legacyDirectory.appendingPathComponent("notes.json")) == legacyNotesData, "legacy files untouched")
        // Inject disk errors: no in-memory optimistic changes or half-applied move.
        let failing = NotesStore(directory: legacyDirectory, writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let beforeFailure = failing.notes
        failing.move(orphanNote, to: failing.folders.first { $0.name == "Bread" }!.id)
        check(failing.notes == beforeFailure && failing.errorMessage != nil, "write failure rolls back recipe move")
        let beforeFolders = failing.folders
        failing.deleteFolder(legacyFolder)
        check(failing.notes == beforeFailure && failing.folders == beforeFolders, "folder deletion cannot partially apply")
        check(!failing.saveRecipe(CookingNote(title: "Unsaved")), "save result signals failure so editor retains draft")
        check(failing.notes.count == beforeFailure.count, "write failure does not publish unsaved recipe")
        check(NotesStore(directory: legacyDirectory).notes == beforeFailure, "failed writes do not alter disk")
        // A damaged library is never replaced by an empty library or its stale legacy copy.
        let libraryURL = legacyDirectory.appendingPathComponent("library.json")
        let damaged = Data("damaged".utf8)
        try damaged.write(to: libraryURL)
        let blocked = NotesStore(directory: legacyDirectory)
        check(!blocked.isAvailable && blocked.errorMessage != nil, "damaged library reported")
        blocked.save(CookingNote(title: "Must not overwrite"))
        check(try Data(contentsOf: libraryURL) == damaged, "damaged data preserved")
        check(!blocked.importLibrary(data), "import cannot replace damaged library")
        try JSONEncoder().encode(RecipeLibraryArchive(notes: [orphanNote], folders: [legacyFolder])).write(to: libraryURL)
        blocked.reload()
        check(blocked.isAvailable && blocked.notes.count == 1, "reload recovers after valid storage restored")
        try damaged.write(to: libraryURL)
        blocked.toggleFavorite(orphanNote)
        let runtimeData = try Data(contentsOf: libraryURL)
        check(!blocked.isAvailable && runtimeData == damaged, "runtime corruption blocks mutation")
        // Malformed legacy state prevents migration instead of erasing it.
        let corruptLegacy = directory.appendingPathComponent("corrupt-legacy")
        try FileManager.default.createDirectory(at: corruptLegacy, withIntermediateDirectories: true)
        try damaged.write(to: corruptLegacy.appendingPathComponent("notes.json"))
        let corrupt = NotesStore(directory: corruptLegacy)
        check(!corrupt.isAvailable && !FileManager.default.fileExists(atPath: corruptLegacy.appendingPathComponent("library.json").path), "bad legacy data is preserved without migration")
        print("Passed \(checks) recipe filesystem checks")
    }
}
