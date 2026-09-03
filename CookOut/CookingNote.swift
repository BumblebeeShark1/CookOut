import Foundation

enum FolderColor: String, Codable, CaseIterable, Identifiable {
    case coral, orange, mango, mint, cyan, berry, indigo
    var id: Self { self }
}

struct RecipeFolder: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var color: FolderColor
    var createdAt: Date

    init(id: UUID = UUID(), name: String, symbol: String = "folder.fill", color: FolderColor = .orange, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.createdAt = createdAt
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", dessert = "Dessert", snack = "Snack", drink = "Drink", other = "Other"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "takeoutbag.and.cup.and.straw"
        case .dinner: "fork.knife"
        case .dessert: "birthday.cake"
        case .snack: "carrot"
        case .drink: "mug"
        case .other: "ellipsis.circle"
        }
    }
}

enum RecipeDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy", medium = "Medium", advanced = "Advanced"
    var id: Self { self }
}

enum RecipeStatus: String, Codable, CaseIterable, Identifiable {
    case idea = "Idea", testing = "Testing", perfected = "Perfected"
    var id: Self { self }
}

struct CookingNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var tags: [String]
    var ingredients: [String]
    var steps: [String]
    var servings: Int
    var prepMinutes: Int
    var cookMinutes: Int
    var mealType: MealType
    var difficulty: RecipeDifficulty
    var status: RecipeStatus
    var rating: Int
    var isFavorite: Bool
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastCookedAt: Date?
    var cookCount: Int
    var folderID: UUID?

    init(id: UUID = UUID(), title: String = "", body: String = "", tags: [String] = [], ingredients: [String] = [], steps: [String] = [], servings: Int = 2, prepMinutes: Int = 0, cookMinutes: Int = 0, mealType: MealType = .dinner, difficulty: RecipeDifficulty = .easy, status: RecipeStatus = .idea, rating: Int = 0, isFavorite: Bool = false, isPinned: Bool = false, createdAt: Date = .now, updatedAt: Date = .now, lastCookedAt: Date? = nil, cookCount: Int = 0, folderID: UUID? = nil) {
        self.id = id; self.title = title; self.body = body; self.tags = tags
        self.ingredients = ingredients; self.steps = steps; self.servings = servings
        self.prepMinutes = prepMinutes; self.cookMinutes = cookMinutes; self.mealType = mealType
        self.difficulty = difficulty; self.status = status; self.rating = rating
        self.isFavorite = isFavorite; self.isPinned = isPinned; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.lastCookedAt = lastCookedAt; self.cookCount = cookCount
        self.folderID = folderID
    }

    var totalMinutes: Int { prepMinutes + cookMinutes }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, tags, ingredients, steps, servings, prepMinutes, cookMinutes
        case mealType, difficulty, status, rating, isFavorite, isPinned, createdAt, updatedAt, lastCookedAt, cookCount, folderID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try values.decodeIfPresent(String.self, forKey: .body) ?? ""
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        ingredients = try values.decodeIfPresent([String].self, forKey: .ingredients) ?? []
        steps = try values.decodeIfPresent([String].self, forKey: .steps) ?? []
        servings = try values.decodeIfPresent(Int.self, forKey: .servings) ?? 2
        prepMinutes = try values.decodeIfPresent(Int.self, forKey: .prepMinutes) ?? 0
        cookMinutes = try values.decodeIfPresent(Int.self, forKey: .cookMinutes) ?? 0
        mealType = try values.decodeIfPresent(MealType.self, forKey: .mealType) ?? .dinner
        difficulty = try values.decodeIfPresent(RecipeDifficulty.self, forKey: .difficulty) ?? .easy
        status = try values.decodeIfPresent(RecipeStatus.self, forKey: .status) ?? .idea
        rating = try values.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        lastCookedAt = try values.decodeIfPresent(Date.self, forKey: .lastCookedAt)
        cookCount = try values.decodeIfPresent(Int.self, forKey: .cookCount) ?? 0
        folderID = try values.decodeIfPresent(UUID.self, forKey: .folderID)
    }
}
