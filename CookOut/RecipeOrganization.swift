import Foundation

enum RecipeCookingFilter: String, Codable, CaseIterable, Identifiable {
    case any = "Any cooking history", never = "Never cooked", cooked = "Cooked before"
    var id: Self { self }
}

enum RecipeDetailFilter: String, Codable, CaseIterable, Identifiable {
    case any = "Any recipe details", untagged = "No tags", missingIngredients = "Needs ingredients", missingDirections = "Needs directions"
    var id: Self { self }
}

struct RecipeCollectionRules: Codable, Equatable {
    var query = ""
    var tags: [String] = []
    var folderID: UUID?
    var unfiledOnly = false
    var meal: MealType?
    var status: RecipeStatus?
    var difficulty: RecipeDifficulty?
    var maxMinutes: Int?
    var minimumRating = 0
    var favoritesOnly = false
    var pinnedOnly = false
    var cookingHistory: RecipeCookingFilter = .any
    var details: RecipeDetailFilter = .any

    var isActive: Bool { self != RecipeCollectionRules() }

    func equivalent(to other: RecipeCollectionRules) -> Bool {
        func canonical(_ value: RecipeCollectionRules) -> RecipeCollectionRules {
            var copy = value
            copy.query = RecipeTags.key(value.query).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            copy.tags = Set(RecipeTags.normalized(value.tags).map(RecipeTags.key)).sorted()
            return copy
        }
        return canonical(self) == canonical(other)
    }

    func validate() throws {
        guard query.count <= 1000, tags.count <= 50, tags.allSatisfy({ !RecipeTags.normalized([$0]).isEmpty && $0.count <= 100 }),
              maxMinutes == nil || (1...1440).contains(maxMinutes!), (0...5).contains(minimumRating),
              !(folderID != nil && unfiledOnly) else { throw RecipeOrganizationError.invalidRules }
    }

    func filter(_ notes: [CookingNote], folders: [RecipeFolder]) -> [CookingNote] {
        guard (try? validate()) != nil else { return [] }
        if let folderID, !folders.contains(where: { $0.id == folderID }) { return [] }
        let scope: RecipeFolderScope = unfiledOnly ? .unfiled : folderID.map { .folder($0) } ?? .all
        return RecipeLibrarySearch.filter(notes, folders: folders, query: query, tags: Set(tags), folderScope: scope, searchAllFolders: false, favoritesOnly: favoritesOnly).filter { matches($0) }
    }

    func matches(_ note: CookingNote) -> Bool {
        guard meal == nil || note.mealType == meal, status == nil || note.status == status,
              difficulty == nil || note.difficulty == difficulty, note.rating >= minimumRating,
              !favoritesOnly || note.isFavorite, !pinnedOnly || note.isPinned,
              maxMinutes == nil || (note.totalMinutes > 0 && note.totalMinutes <= maxMinutes!) else { return false }
        switch cookingHistory {
        case .any: break
        case .never: if note.cookCount != 0 { return false }
        case .cooked: if note.cookCount == 0 { return false }
        }
        switch details {
        case .any: break
        case .untagged: if !RecipeTags.normalized(note.tags).isEmpty { return false }
        case .missingIngredients: if !note.ingredients.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return false }
        case .missingDirections: if !note.steps.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return false }
        }
        return true
    }
}

struct RecipeSmartCollection: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rules: RecipeCollectionRules

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw RecipeOrganizationError.invalidRules }
        try rules.validate()
    }
}

struct RecipeBatchChanges {
    var addTags: [String] = []
    var removeTags: [String] = []
    var changeFolder = false
    var folderID: UUID?
    var meal: MealType?
    var status: RecipeStatus?
    var favorite: Bool?
    var pinned: Bool?
    var hasChanges: Bool { !addTags.isEmpty || !removeTags.isEmpty || changeFolder || meal != nil || status != nil || favorite != nil || pinned != nil }

    func validate() throws {
        guard hasChanges, addTags.count <= 50, removeTags.count <= 50,
              (addTags + removeTags).allSatisfy({ !RecipeTags.normalized([$0]).isEmpty && $0.count <= 100 }) else { throw RecipeOrganizationError.invalidRules }
    }

    func applying(to note: CookingNote) -> CookingNote {
        var copy = note
        let removed = Set(RecipeTags.normalized(removeTags).map(RecipeTags.key))
        copy.tags = RecipeTags.normalized(RecipeTags.normalized(note.tags).filter { !removed.contains(RecipeTags.key($0)) } + addTags)
        if changeFolder { copy.folderID = folderID }
        if let meal { copy.mealType = meal }
        if let status { copy.status = status }
        if let favorite { copy.isFavorite = favorite }
        if let pinned { copy.isPinned = pinned }
        return copy
    }
}

enum RecipeOrganizationError: LocalizedError {
    case invalidRules, invalidSelection, duplicateName, staleReview
    var errorDescription: String? {
        switch self {
        case .invalidRules: "Check the collection name, tags, rating, and cooking-time filters."
        case .invalidSelection: "Some selected recipes or the destination folder no longer exist. Refresh the library and select them again."
        case .duplicateName: "A smart collection already uses that name. Choose another name."
        case .staleReview: "This recipe changed after the filing suggestion was prepared. Review the updated suggestion before applying it."
        }
    }
}

struct RecipeDuplicateGroup: Identifiable {
    let id: String
    let reason: String
    let recipes: [CookingNote]
}

enum RecipeOrganization {
    /// Group matching source URLs or exact normalized content. Titles alone
    /// never establish duplication: family variations keep their identities.
    static func duplicates(in notes: [CookingNote]) -> [RecipeDuplicateGroup] {
        func normalized(_ text: String) -> String {
            RecipeTags.key(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func sourceKey(_ note: CookingNote) -> String? {
            guard let text = note.sourceURL, let parts = URLComponents(string: text),
                  ["http", "https"].contains(parts.scheme ?? ""), let host = parts.host else { return nil }
            let path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lowerHost = host.lowercased()
            let cleanHost = lowerHost.hasPrefix("www.") ? String(lowerHost.dropFirst(4)) : lowerHost
            let query = (parts.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid"].contains($0.name.lowercased()) }
                .sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name }
            var canonical = URLComponents(); canonical.queryItems = query.isEmpty ? nil : query
            return cleanHost + "/" + path + (canonical.percentEncodedQuery.map { "?" + $0 } ?? "")
        }
        var grouped: [String: [CookingNote]] = [:]
        for note in notes {
            if let source = sourceKey(note) { grouped["source:" + source, default: []].append(note) }
            let ingredients = note.ingredients.map(normalized).filter { !$0.isEmpty }
            let steps = note.steps.map(normalized).filter { !$0.isEmpty }
            let body = normalized(note.body)
            guard !ingredients.isEmpty || !steps.isEmpty || !body.isEmpty else { continue }
            // JSON preserves boundaries between ingredient and instruction lines.
            var title = normalized(note.title)
            while title.hasSuffix(" copy") { title = String(title.dropLast(5)) }
            let values = [title, body, String(note.servings)] + [ingredients.joined(separator: "\n"), steps.joined(separator: "\n")]
            if let data = try? JSONEncoder().encode(values) { grouped["content:" + String(decoding: data, as: UTF8.self), default: []].append(note) }
        }
        var seen = Set<String>()
        return grouped.sorted { $0.key < $1.key }.compactMap { key, recipes in
            let unique = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.createdAt < $1.createdAt }
            guard unique.count > 1 else { return nil }
            let identity = unique.map { $0.id.uuidString }.sorted().joined(separator: ",")
            guard seen.insert(identity).inserted else { return nil }
            return RecipeDuplicateGroup(id: key, reason: key.hasPrefix("source:") ? "Same source link — versions may differ" : "Matching title, yield, ingredients, and directions", recipes: unique)
        }
    }

    static func tagCounts(in notes: [CookingNote]) -> [(tag: String, count: Int)] {
        let tags = RecipeTags.available(in: notes)
        return tags.map { tag in (tag, notes.filter { Set(RecipeTags.normalized($0.tags).map(RecipeTags.key)).contains(RecipeTags.key(tag)) }.count) }
    }

    static func suggestedFolder(for note: CookingNote, folders: [RecipeFolder]) -> RecipeFolder? {
        let words = Set(RecipeTags.key(note.title).split(whereSeparator: { !$0.isLetter }).map(String.init))
        func named(_ name: String) -> RecipeFolder? { folders.first { $0.parentID == nil && RecipeTags.key($0.name) == RecipeTags.key(name) } }
        if !words.isDisjoint(with: ["bread", "loaf", "sourdough", "baguette", "focaccia", "rolls"]) { return named("Bread") }
        if !words.isDisjoint(with: ["sauce", "salsa", "dressing", "marinade", "pesto", "dip", "hummus"]) { return named("Sauces") }
        if !words.isDisjoint(with: ["soup", "stew", "chowder", "broth"]) { return named("Soups & stews") }
        if !words.isDisjoint(with: ["salad", "slaw"]) { return named("Salads & sides") }
        switch note.mealType {
        case .breakfast: return named("Breakfast")
        case .dessert: return named("Desserts")
        case .drink: return named("Drinks")
        case .dinner: return named("Entrées")
        case .lunch, .snack, .other: return nil
        }
    }
}
