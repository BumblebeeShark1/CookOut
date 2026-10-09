import Foundation

@main
struct RecipeLibrarySearchTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            checks += 1
            guard value else { fatalError("FAIL: \(name)") }
        }
        let garden = RecipeFolder(name: "From the garden")
        let baking = RecipeFolder(name: "Sunday baking")
        var pasta = CookingNote()
        pasta.title = "Tomato pasta"
        pasta.body = "Grandma’s favorite"
        pasta.ingredients = ["500 g tomatoes", "1 tbsp olive oil"]
        pasta.steps = ["Roast until caramelized"]
        pasta.tags = ["Dinner", "Family favorites"]
        pasta.folderID = garden.id
        pasta.isFavorite = true
        var cake = CookingNote()
        cake.title = "Lemon cake"
        cake.tags = ["family favorites", "Baking", "Café"]
        cake.ingredients = ["2 lemons"]
        cake.folderID = baking.id
        var soup = CookingNote()
        soup.title = "White bean soup"
        soup.tags = ["Dinner"]
        let notes = [pasta, cake, soup]
        let folders = [garden, baking]
        func results(_ query: String = "", tags: Set<String> = [], scope: RecipeFolderScope = .all,
                     across: Bool = true, favorites: Bool = false) -> [UUID] {
            RecipeLibrarySearch.filter(notes, folders: folders, query: query, tags: tags,
                                       folderScope: scope, searchAllFolders: across, favoritesOnly: favorites).map(\.id)
        }
        check(results(scope: .folder(garden.id)) == [pasta.id], "browsing respects current folder")
        check(results("lemon", scope: .folder(garden.id)) == [cake.id], "search crosses selected folder")
        check(results("lemon", scope: .folder(garden.id), across: false).isEmpty, "current collection scope")
        check(results("family favorites", scope: .folder(garden.id)) == [pasta.id, cake.id], "text finds tags across folders")
        check(results(tags: ["FAMILY FAVORITES"], scope: .folder(garden.id)) == [pasta.id, cake.id], "shared tag cross-references both folders")
        check(results(tags: ["Family favorites", "Dinner"]) == [pasta.id], "multiple selected tags require all")
        check(results(tags: ["Family favorites", "Dinner"]).count == 1, "one recipe appears once for several tags")
        check(results(tags: ["Dinner"], scope: .unfiled) == [pasta.id, soup.id], "tags cross unfiled boundary")
        check(results(tags: ["Dinner"], scope: .unfiled, across: false) == [soup.id], "unfiled scope when requested")
        check(results(tags: ["Family favorites"], favorites: true) == [pasta.id], "favorites preserved during global tag search")
        check(results("lemon", favorites: true).isEmpty, "global search does not leak nonfavorites")
        check(results("caramelized") == [pasta.id], "search directions")
        check(results("olive") == [pasta.id], "search ingredients")
        check(results("grandma") == [pasta.id], "search notes")
        check(results("Sunday baking") == [cake.id], "search folder names")
        check(results("unfiled") == [soup.id], "search unfiled name")
        check(results("tomato roast garden") == [pasta.id], "terms match across title directions and folder")
        check(results("tomato lemons").isEmpty, "every text term required")
        check(results("LEMON") == [cake.id], "case insensitive")
        check(results("cafe") == [cake.id], "accent insensitive")
        check(results(tags: ["cafe"]) == [cake.id], "accent insensitive tag identity")
        check(results(" \n\t", scope: .folder(baking.id)) == [cake.id], "whitespace is not an active search")
        check(results("lemon", tags: ["Dinner"]).isEmpty, "text and tag combine")
        check(results(tags: ["missing"]).isEmpty, "unknown tag empty results")
        check(results(scope: .folder(UUID())).isEmpty, "missing folder no browse results")
        check(results("tomato", scope: .folder(UUID())) == [pasta.id], "search survives stale folder selection")
        check(RecipeTags.parse(" #Dinner, dinner, , Café, cafe\nBaking\r\n##Family favorites ") == ["Dinner", "Café", "Baking", "Family favorites"], "normalize tag entry and duplicates")
        check(RecipeTags.parse(" , #, \n").isEmpty, "empty tag entry")
        check(RecipeTags.normalized(["family favorites", "family", "favorites"]).count == 3, "multiword tag remains a single tag")
        check(RecipeTags.available(in: notes).filter { RecipeTags.key($0) == "family favorites" }.count == 1, "shared spelling appears as one filter")
        check(RecipeTags.available(in: []).isEmpty, "empty cookbook tags")
        check(RecipeLibrarySearch.filter([], folders: [], query: "x", tags: [], folderScope: .all, searchAllFolders: true, favoritesOnly: false).isEmpty, "empty cookbook search")
        check(RecipeLibrarySearch.filter(notes, folders: [garden, garden, baking], query: "garden", tags: [], folderScope: .all, searchAllFolders: true, favoritesOnly: false).map(\.id) == [pasta.id], "duplicate folder IDs do not crash")
        var orphan = cake
        orphan.folderID = UUID()
        check(RecipeLibrarySearch.filter([orphan], folders: [], query: "lemon", tags: [], folderScope: .all, searchAllFolders: true, favoritesOnly: false).count == 1, "orphan recipe searchable")
        let encoded = try JSONEncoder().encode(pasta)
        let restored = try JSONDecoder().decode(CookingNote.self, from: encoded)
        check(restored.tags == pasta.tags && restored.id == pasta.id && restored.folderID == pasta.folderID, "tags preserve recipe identity and folder on reload")
        check(notes[0] == pasta && notes[1] == cake, "search never mutates recipes")
        print("Passed \(checks) recipe search and tag checks")
    }
}
