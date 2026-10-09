import Foundation
import Combine

struct BankRecipe: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let ingredients: [String]
    let sourceURL: String
    let publisher: String
    let mealType: MealType
    let cuisine: String
    let foodGroups: [String]
    let prepMinutes: Int?
    let cookMinutes: Int?
    let totalMinutes: Int?
    let servings: Int?
    let selectionScore: Int

    var url: URL? { RecipeSourceURL.valid(sourceURL) }
    var searchText: String { RecipeIngredientIdentity.key(([title, cuisine, publisher] + ingredients + foodGroups).joined(separator: " ")) }

    func note() -> CookingNote {
        var note = CookingNote(id: id, title: title,
            body: "Source-linked recipe from \(publisher). Open the original recipe for cooking directions and current ingredient quantities. Food-group labels describe ingredient matches, not measured nutrient intake.",
            tags: [cuisine] + foodGroups, ingredients: ingredients, steps: [], servings: servings ?? 2,
            prepMinutes: prepMinutes ?? 0, cookMinutes: cookMinutes ?? 0, mealType: mealType)
        note.sourceURL = sourceURL
        note.sourcePublisher = publisher
        note.sourceYieldIsServings = servings != nil
        return note
    }

    func validate() throws {
        guard !title.isEmpty, title.count <= 250, url != nil, !publisher.isEmpty, publisher.count <= 100,
              (1...50).contains(ingredients.count), ingredients.allSatisfy({ !$0.isEmpty && $0.count <= 500 }),
              cuisine.count <= 100, foodGroups.count <= 10,
              [prepMinutes, cookMinutes, totalMinutes].allSatisfy({ $0 == nil || (0...1440).contains($0!) }),
              servings == nil || (1...24).contains(servings!) else { throw RecipeBankError.invalidCatalog }
    }
}

enum RecipeSourceURL {
    static func valid(_ text: String) -> URL? {
        guard text.count <= 2000, let parts = URLComponents(string: text), parts.scheme == "https",
              let host = parts.host, host.contains("."), !host.contains(" "),
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              !["localhost", "127.0.0.1", "::1"].contains(host) else { return nil }
        return parts.url
    }
}

enum RecipeBankError: LocalizedError {
    case missingCatalog, invalidCatalog
    var errorDescription: String? {
        "The recipe bank could not be opened. Your personal cookbook and meal plan are unchanged. Try reopening CookOut."
    }
}

struct RecipeBankCatalog: Codable {
    let version: Int
    let catalogName: String
    let compiledAt: String
    let attribution: String
    let licenseURL: String
    let datasetURL: String
    let nutritionGuidanceURL: String
    let notes: String
    let recipes: [BankRecipe]

    static func decode(_ data: Data) throws -> RecipeBankCatalog {
        guard data.count <= 30_000_000 else { throw RecipeBankError.invalidCatalog }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.version == 1, (5000...20_000).contains(catalog.recipes.count),
              Set(catalog.recipes.map(\.id)).count == catalog.recipes.count,
              Set(catalog.recipes.map(\.sourceURL)).count == catalog.recipes.count else { throw RecipeBankError.invalidCatalog }
        for recipe in catalog.recipes { try recipe.validate() }
        return catalog
    }
}

@MainActor
final class RecipeBankStore: ObservableObject {
    @Published private(set) var catalog: RecipeBankCatalog?
    @Published private(set) var errorMessage: String?
    var recipes: [BankRecipe] { catalog?.recipes ?? [] }
    private var lookup: [UUID: BankRecipe] = [:]

    init(catalogURL: URL? = nil) {
        do {
            guard let url = catalogURL ?? Bundle.main.url(forResource: "recipe-bank", withExtension: "json") ?? Bundle.main.url(forResource: "recipe-bank", withExtension: "json", subdirectory: "Resources") else { throw RecipeBankError.missingCatalog }
            let decoded = try RecipeBankCatalog.decode(Data(contentsOf: url))
            catalog = decoded
            lookup = Dictionary(uniqueKeysWithValues: decoded.recipes.map { ($0.id, $0) })
        } catch { errorMessage = error.localizedDescription }
    }

    func recipe(_ id: UUID) -> BankRecipe? { lookup[id] }
    func search(query: String, meal: MealType? = nil, cuisine: String? = nil, group: String? = nil, maxMinutes: Int? = nil) -> [BankRecipe] {
        let terms = RecipeIngredientIdentity.key(query).split(whereSeparator: \.isWhitespace)
        return recipes.filter { recipe in
            guard meal == nil || recipe.mealType == meal, cuisine == nil || recipe.cuisine == cuisine,
                  group == nil || recipe.foodGroups.contains(group!),
                  maxMinutes == nil || recipe.totalMinutes.map({ $0 <= maxMinutes! }) == true else { return false }
            return terms.isEmpty || terms.allSatisfy { recipe.searchText.contains($0) }
        }
    }
}

enum RecipeIngredientIdentity {
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whole word matching prevents "egg" from matching eggplant, and "nut"
    /// from matching nutmeg. This filters known ingredients; it is not a
    /// certification of allergen absence or of cross-contamination safety.
    static func contains(_ ingredient: String, term: String) -> Bool {
        let needle = key(term)
        guard !needle.isEmpty else { return false }
        let text = key(ingredient)
        func isLetter(_ character: Character) -> Bool { character >= "a" && character <= "z" }
        // Literal matching avoids compiling a regular expression for each of
        // the thousands of catalog ingredient checks, preserving word bounds.
        for word in [needle, needle + "s", needle + "es"] {
            var start = text.startIndex
            while start < text.endIndex, let range = text.range(of: word, options: .literal, range: start..<text.endIndex) {
                let left = range.lowerBound == text.startIndex || !isLetter(text[text.index(before: range.lowerBound)])
                let right = range.upperBound == text.endIndex || !isLetter(text[range.upperBound])
                if left && right { return true }
                start = text.index(after: range.lowerBound)
            }
        }
        return false
    }
}
