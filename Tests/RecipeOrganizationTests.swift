import Foundation

@main struct RecipeOrganizationTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ result: Bool, _ name: String) { checks += 1; if !result { fatalError("FAIL: \(name)") } }
        func rejects(_ name: String, _ action: () throws -> Void) { do { try action(); check(false, name) } catch { check(true, name) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CookOut-organization-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = NotesStore(directory: root)
        let dinnerFolder = store.folders.first { $0.name == "Entrées" }!
        let breadFolder = store.folders.first { $0.name == "Bread" }!
        let nested = store.folders.first { $0.name == "Seafood" }!
        var quick = CookingNote(title: "Lentil dinner", body: "Family version", tags: ["Weeknight", "Family"], ingredients: ["1 cup lentils", "2 carrots"], steps: ["Simmer lentils."], servings: 4, prepMinutes: 5, cookMinutes: 20, mealType: .dinner, rating: 4, isFavorite: true, folderID: nested.id)
        quick.sourceURL = "https://example.com/recipes/lentil"; quick.sourcePublisher = "Example"; quick.sourceYieldIsServings = true
        let slow = CookingNote(title: "Sunday stew", tags: ["Family"], ingredients: ["Beans"], steps: ["Simmer."], prepMinutes: 20, cookMinutes: 80, mealType: .dinner, difficulty: .advanced, status: .perfected, rating: 5, cookCount: 3, folderID: dinnerFolder.id)
        let incomplete = CookingNote(title: "Untested loaf", mealType: .snack)
        check(store.addRecipes([quick, slow, incomplete], to: nil), "add a selection atomically")
        check(store.moveRecipes([quick.id], to: nested.id) && store.moveRecipes([slow.id], to: dinnerFolder.id), "existing folder organization")
        let notes = store.notes
        var rules = RecipeCollectionRules(tags: ["family"], folderID: dinnerFolder.id, meal: .dinner, maxMinutes: 30, minimumRating: 4, favoritesOnly: true, cookingHistory: .never)
        check(rules.filter(notes, folders: store.folders).map(\.id) == [quick.id], "combined rules include nested folders and normalized tags")
        rules.maxMinutes = nil
        check(rules.filter(notes, folders: store.folders).count == 1, "favorite and history rules remain applied")
        rules.favoritesOnly = false; rules.cookingHistory = .cooked
        check(rules.filter(notes, folders: store.folders).map(\.id) == [slow.id], "cooked recipe collection")
        check(RecipeCollectionRules(details: .untagged).filter(notes, folders: store.folders).map(\.id) == [incomplete.id], "untagged collection")
        check(RecipeCollectionRules(details: .missingIngredients).filter(notes, folders: store.folders).map(\.id) == [incomplete.id], "missing ingredients collection")
        check(RecipeCollectionRules(details: .missingDirections).filter(notes, folders: store.folders).map(\.id) == [incomplete.id], "missing directions collection")
        check(RecipeCollectionRules(unfiledOnly: true).filter(notes, folders: store.folders).map(\.id) == [incomplete.id], "unfiled collection")
        check(RecipeCollectionRules(maxMinutes: 30).filter(notes, folders: store.folders).map(\.id) == [quick.id], "unknown cooking time excluded")
        check(RecipeCollectionRules(status: .perfected, difficulty: .advanced).filter(notes, folders: store.folders).map(\.id) == [slow.id], "status and difficulty collection")
        check(RecipeCollectionRules(folderID: UUID()).filter(notes, folders: store.folders).isEmpty, "missing saved folder never broadens results")
        check(RecipeCollectionRules(query: "family lentil").filter(notes, folders: store.folders).map(\.id) == [quick.id], "words search across recipe fields")
        check(RecipeCollectionRules(tags: ["Family", "Weeknight"]).filter(notes, folders: store.folders).map(\.id) == [quick.id], "all tag criteria required")
        check(RecipeCollectionRules(query: " Lentil   Dinner ", tags: ["Family", "WEEKnight"]).equivalent(to: RecipeCollectionRules(query: "lentil dinner", tags: ["weeknight", "family"])), "rule identity ignores tag order, case, and query spacing")
        var invalid = RecipeCollectionRules(); invalid.maxMinutes = -1
        rejects("invalid time limit") { try invalid.validate() }
        check(invalid.filter(notes, folders: store.folders).isEmpty, "malformed rules match nothing")
        invalid = RecipeCollectionRules(folderID: dinnerFolder.id, unfiledOnly: true)
        rejects("contradictory folder rules") { try invalid.validate() }
        invalid = RecipeCollectionRules(minimumRating: 6)
        rejects("invalid rating") { try invalid.validate() }
        invalid = RecipeCollectionRules(tags: [String(repeating: "x", count: 101)])
        rejects("oversized tag") { try invalid.validate() }
        let collection = RecipeSmartCollection(name: "Quick family dinners", rules: RecipeCollectionRules(tags: ["Family", "Weeknight"], meal: .dinner, maxMinutes: 30))
        check(store.saveCollection(collection), "save smart collection")
        check(store.smartCollections[0].rules.filter(store.notes, folders: store.folders).map(\.id) == [quick.id], "collection membership")
        let secondQuick = CookingNote(title: "Bean dinner", tags: ["Family", "Weeknight"], ingredients: ["Beans"], cookMinutes: 15, mealType: .dinner)
        check(store.saveRecipe(secondQuick), "add another matching recipe")
        check(store.smartCollections[0].rules.filter(store.notes, folders: store.folders).count == 2, "membership updates as library changes")
        check(!store.saveCollection(RecipeSmartCollection(name: " quick FAMILY dinners ", rules: RecipeCollectionRules())), "duplicate collection name rejected")
        let restarted = NotesStore(directory: root)
        check(restarted.smartCollections == store.smartCollections, "collections survive restart")
        check(restarted.notes.map(\.id).sorted { $0.uuidString < $1.uuidString } == store.notes.map(\.id).sorted { $0.uuidString < $1.uuidString }, "collection save preserves IDs")
        let persistedQuick = store.notes.first { $0.id == quick.id }!
        var batch = RecipeBatchChanges(addTags: ["Weeknight", "Quick"], removeTags: ["Family"], changeFolder: true, folderID: breadFolder.id, status: .testing, favorite: true, pinned: true)
        check(store.organizeRecipes([quick.id, secondQuick.id], changes: batch), "bulk tags, folder, status, favorites, and pins")
        let changed = store.notes.first { $0.id == quick.id }!
        check(changed.tags == ["Weeknight", "Quick"], "bulk add and remove tags without duplicates")
        check(changed.folderID == breadFolder.id && changed.status == .testing && changed.isFavorite && changed.isPinned, "bulk field choices applied")
        check(changed.ingredients == persistedQuick.ingredients && changed.steps == persistedQuick.steps && changed.body == persistedQuick.body && changed.servings == persistedQuick.servings, "recipe content preserved")
        check(changed.sourceURL == quick.sourceURL && changed.sourcePublisher == quick.sourcePublisher && changed.sourceYieldIsServings == quick.sourceYieldIsServings && changed.createdAt == quick.createdAt && changed.cookCount == quick.cookCount, "provenance and cooking history preserved")
        check(store.notes.first { $0.id == slow.id } == notes.first { $0.id == slow.id }, "unselected recipe unchanged")
        let before = store.notes
        check(!store.organizeRecipes([quick.id, UUID()], changes: batch) && store.notes == before, "missing selected recipe refuses entire batch")
        batch.folderID = UUID()
        check(!store.organizeRecipes([quick.id], changes: batch) && store.notes == before, "missing destination refuses entire batch")
        check(!store.organizeRecipes([quick.id], changes: RecipeBatchChanges()), "empty bulk changes rejected")
        check(!store.organizeRecipes([], changes: RecipeBatchChanges(addTags: ["tag"])), "empty selection rejected")
        check(store.renameTag("Weeknight", to: "Quick"), "rename into an existing tag")
        check(store.notes.first { $0.id == quick.id }!.tags == ["Quick"], "tag merge removes repeats within recipes")
        check(Set(store.smartCollections.first!.rules.tags) == ["Family", "Quick"], "tag-based collection references update together")
        check(!store.renameTag("Quick", to: " "), "empty rename rejected")
        check(!store.renameTag("Quick", to: "two,tags"), "rename is a single tag")
        check(!store.renameTag("Quick", to: String(repeating: "x", count: 101)), "oversized rename rejected")
        let messy = CookingNote(title: "Messy tags", tags: [" #QUICK ", "Quick"])
        check(store.saveRecipe(messy) && store.renameTag("Quick", to: "Easy"), "rename handles imported whitespace and hash prefixes")
        check(store.notes.first { $0.id == messy.id }?.tags == ["Easy"], "imported tag spellings normalized")
        let counts = RecipeOrganization.tagCounts(in: store.notes)
        check(counts.first { $0.tag == "Easy" }?.count == 3, "tag counts count each recipe once")
        let export = try store.exportLibrary()
        let exported = try JSONDecoder().decode(RecipeLibraryArchive.self, from: export)
        check(exported.smartCollections == store.smartCollections, "backup includes collections")
        let importedDir = root.appendingPathComponent("imported")
        let importer = NotesStore(directory: importedDir)
        var folderCollection = collection; folderCollection.id = UUID(); folderCollection.name = "Bread recipes"; folderCollection.rules = RecipeCollectionRules(folderID: breadFolder.id)
        check(store.saveCollection(folderCollection), "folder-based collection saved")
        check(importer.importLibrary(try store.exportLibrary()), "import collections with cookbook")
        let importedRule = importer.smartCollections.first { $0.name == "Bread recipes" }!.rules
        check(importedRule.folderID != breadFolder.id && importer.folders.contains { $0.id == importedRule.folderID }, "import remaps collection folder identity")
        check(importedRule.filter(importer.notes, folders: importer.folders).count == 2, "imported collection selects imported recipes")
        check(importer.importLibrary(try store.exportLibrary()), "repeat import creates independent collections")
        check(Set(importer.smartCollections.map(\.name)).count == importer.smartCollections.count, "import collection names disambiguated")
        var duplicateArchive = exported; duplicateArchive.smartCollections = [collection, collection]
        rejects("duplicate saved collection IDs") { try duplicateArchive.validate() }
        var legacyObject = try JSONSerialization.jsonObject(with: export) as! [String: Any]; legacyObject.removeValue(forKey: "smartCollections")
        let legacy = try JSONDecoder().decode(RecipeLibraryArchive.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        check(legacy.smartCollections == nil && legacy.reconciled().notes.count == store.notes.count, "old library schema remains compatible")
        var edited = quick; edited.title = "My edited version"; edited.tags = ["Mine"]
        check(store.saveRecipe(edited), "personal edited bank copy")
        let newBank = CookingNote(title: "New source recipe", tags: ["Italian"], ingredients: ["Rice"])
        check(store.addRecipes([quick, newBank], to: dinnerFolder.id, tags: ["Weeknight"]), "bank import adds only new IDs")
        check(store.notes.first { $0.id == quick.id }?.title == "My edited version" && store.notes.first { $0.id == quick.id }?.tags == ["Mine"], "bank import never overwrites an edited copy")
        check(store.notes.first { $0.id == newBank.id }?.folderID == dinnerFolder.id && store.notes.first { $0.id == newBank.id }?.tags == ["Italian", "Weeknight"], "new bank recipe is filed and tagged")
        check(!store.addRecipes([newBank, newBank], to: nil), "duplicate IDs within batch rejected")
        check(!store.addRecipes([CookingNote(title: "Orphan")], to: UUID()), "invalid bank destination rejected")
        check(!store.addRecipes((0..<251).map { CookingNote(title: "Recipe \($0)") }, to: nil), "import size bounded")
        let parallel = NotesStore(directory: root)
        let newConcurrent = CookingNote(title: "Other window")
        check(parallel.saveRecipe(newConcurrent), "another window saves recipe")
        check(store.organizeRecipes([quick.id], changes: RecipeBatchChanges(addTags: ["Organized"])), "stale window bulk edit reads latest library")
        check(store.notes.contains { $0.id == newConcurrent.id }, "bulk edit preserves other-window additions")
        check(store.smartCollections.count == 2, "unrelated edits preserve collection metadata")
        let unfiled = store.notes.first { $0.id == incomplete.id }!
        check(RecipeOrganization.suggestedFolder(for: unfiled, folders: store.folders)?.id == breadFolder.id, "unfiled title suggestion")
        var revised = unfiled; revised.title = "Loaf changed elsewhere"
        check(parallel.saveRecipe(revised), "recipe changes after suggestion")
        check(!store.fileSuggestedRecipe(unfiled, to: breadFolder.id), "stale suggestion cannot overwrite recipe changes")
        store.reload()
        let fresh = store.notes.first { $0.id == unfiled.id }!
        check(store.fileSuggestedRecipe(fresh, to: breadFolder.id), "reviewed current suggestion files recipe")
        check(!store.fileSuggestedRecipe(fresh, to: dinnerFolder.id), "suggestion never moves an already-filed recipe")
        let dessert = CookingNote(title: "Chocolate cake", mealType: .dessert)
        check(RecipeOrganization.suggestedFolder(for: dessert, folders: store.folders)?.name == "Desserts", "meal-type suggestion")
        check(RecipeOrganization.suggestedFolder(for: CookingNote(title: "Eggplant salad", mealType: .lunch), folders: store.folders)?.name == "Salads & sides", "title category matching")
        check(RecipeOrganization.suggestedFolder(for: CookingNote(title: "Breadfruit", mealType: .other), folders: store.folders) == nil, "category suggestions use whole words")
        check(RecipeOrganization.suggestedFolder(for: dessert, folders: []) == nil, "no invented destination folders")
        var sameSource = quick; sameSource.id = UUID(); sameSource.title = "An improved version"; sameSource.ingredients = ["Different ingredients"]
        check(RecipeOrganization.duplicates(in: [quick, sameSource]).count == 1, "same source marked for version review")
        var copy = quick; copy.id = UUID(); copy.sourceURL = nil; copy.title = quick.title + " Copy"
        var originalWithoutSource = quick; originalWithoutSource.sourceURL = nil
        check(RecipeOrganization.duplicates(in: [originalWithoutSource, copy]).count == 1, "app-created content copy found")
        var variation = copy; variation.steps = ["Roast instead."]
        check(RecipeOrganization.duplicates(in: [originalWithoutSource, variation]).isEmpty, "different directions preserve legitimate variations")
        let emptyA = CookingNote(title: "Soup"), emptyB = CookingNote(title: "Soup")
        check(RecipeOrganization.duplicates(in: [emptyA, emptyB]).isEmpty, "same empty title alone is not duplication")
        var queryA = quick; queryA.sourceURL = "https://example.com/recipe?id=1"; queryA.body = "One"
        var queryB = sameSource; queryB.sourceURL = "https://example.com/recipe?id=2"; queryB.body = "Two"
        check(RecipeOrganization.duplicates(in: [queryA, queryB]).isEmpty, "meaningful URL query parameters distinguish recipes")
        queryB.sourceURL = "http://www.example.com/recipe?id=1&utm_source=newsletter"
        check(RecipeOrganization.duplicates(in: [queryA, queryB]).count == 1, "tracking URLs normalize for source review")
        let fail = NotesStore(directory: root, writeData: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let failNotes = fail.notes, failCollections = fail.smartCollections
        check(!fail.organizeRecipes([quick.id], changes: RecipeBatchChanges(addTags: ["Failed"])), "bulk write failure reported")
        check(!fail.renameTag("Easy", to: "Failed"), "tag rename write failure reported")
        check(!fail.saveCollection(RecipeSmartCollection(name: "Unsaved", rules: RecipeCollectionRules())), "collection write failure reported")
        check(!fail.addRecipes([CookingNote(title: "Unsaved bank")], to: nil), "bank import write failure reported")
        check(fail.notes == failNotes && fail.smartCollections == failCollections, "failed writes preserve recipes and collections together")
        let savedURL = root.appendingPathComponent("library.json")
        var corrupted = try JSONDecoder().decode(RecipeLibraryArchive.self, from: Data(contentsOf: savedURL))
        corrupted.smartCollections![0].rules.minimumRating = 99
        let corruptData = try JSONEncoder().encode(corrupted); try corruptData.write(to: savedURL)
        let blocked = NotesStore(directory: root)
        check(!blocked.isAvailable && !blocked.saveCollection(collection), "malformed collection blocks mutation of corrupt library")
        check(try Data(contentsOf: savedURL) == corruptData, "malformed library preserved for recovery")
        print("PASS: \(checks) recipe organization checks")
    }
}
