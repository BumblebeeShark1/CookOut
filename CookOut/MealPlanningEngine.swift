import Foundation

struct PlanningPreferences: Codable, Equatable {
    var householdSize = 2
    var meals: [MealType] = [.breakfast, .lunch, .dinner]
    var maxCookingMinutes = 60
    var avoidIngredients: [String] = []
    var pantryItems: [String] = []
    var preferredCuisines: [String] = []
    var budgetMindful = true
    var useLeftovers = true
    var allowUnknownTimes = false

    func validate() throws {
        guard (1...12).contains(householdSize), (10...240).contains(maxCookingMinutes),
              (1...6).contains(meals.count), Set(meals).count == meals.count, !meals.contains(.other),
              avoidIngredients.count <= 40, pantryItems.count <= 200, preferredCuisines.count <= 30,
              (avoidIngredients + pantryItems + preferredCuisines).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 100 }) else { throw MealPlanningError.invalidPreferences }
    }
}

enum MealPlanningError: LocalizedError {
    case invalidPreferences, noCandidates(MealType), invalidDraft, planChanged
    var errorDescription: String? {
        switch self {
        case .invalidPreferences: "Check household size, cooking time, meal choices, and ingredient preferences."
        case .noCandidates(let meal): "No suitable \(meal.rawValue.lowercased()) recipes matched these preferences. Adjust the cooking time or ingredient exclusions, or add a recipe."
        case .invalidDraft: "This meal-plan draft was incomplete or did not match your preferences. Nothing was saved."
        case .planChanged: "Your week changed while this draft was being prepared. Generate a new draft so your latest meals are preserved."
        }
    }
}

struct PlanningCandidate: Identifiable {
    let note: CookingNote
    let foodGroups: [String]
    let cuisine: String
    let minutes: Int?
    var id: UUID { note.id }
}

struct MealPlanDraft: Identifiable {
    let id = UUID()
    var entries: [PlannedMeal]
    var explanation: String
    var prepNotes: [String]
    let baseline: [PlannedMeal]
    let days: Set<String>
    let preferences: PlanningPreferences
}

enum MealPlanningEngine {
    static func candidates(personal: [CookingNote], bank: [BankRecipe], preferences: PlanningPreferences) -> [PlanningCandidate] {
        var seen = Set<UUID>()
        let personalCandidates = personal.map { PlanningCandidate(note: $0, foodGroups: RecipeFoodGroups.infer($0.ingredients), cuisine: $0.tags.first ?? "Personal cookbook", minutes: $0.totalMinutes > 0 ? $0.totalMinutes : nil) }
        let bankCandidates = bank.map { PlanningCandidate(note: $0.note(), foodGroups: $0.foodGroups, cuisine: $0.cuisine, minutes: $0.totalMinutes) }
        return (personalCandidates + bankCandidates).filter { candidate in
            guard seen.insert(candidate.id).inserted, !candidate.note.ingredients.isEmpty,
                  preferences.allowUnknownTimes || candidate.minutes != nil,
                  candidate.minutes == nil || candidate.minutes! <= preferences.maxCookingMinutes else { return false }
            return !IngredientExclusions.matches(candidate.note.ingredients, excluded: preferences.avoidIngredients)
        }
    }

    static func generate(days: [String], existing: [PlannedMeal], candidates: [PlanningCandidate], preferences: PlanningPreferences) throws -> MealPlanDraft {
        try preferences.validate()
        guard (1...14).contains(days.count), Set(days).count == days.count, days.allSatisfy({ MealPlanDate.date($0) != nil }) else { throw MealPlanningError.invalidDraft }
        let orderedDays = days.sorted()
        let baseline = existing.filter { days.contains($0.day) }
        var draft: [PlannedMeal] = []
        var used = Set(baseline.map(\.recipeID))
        var cuisineCounts: [String: Int] = [:]
        var proteinCounts: [String: Int] = [:]
        // Profiling the full bank showed ingredient matching repeated during
        // every comparison. Compute recipe-invariant facts once per draft.
        let families = Dictionary(candidates.map { ($0.id, RecipeFoodGroups.proteinFamily($0.note.ingredients)) }, uniquingKeysWith: { first, _ in first })
        let baseScores = Dictionary(candidates.map { ($0.id, score($0, preferences: preferences)) }, uniquingKeysWith: { first, _ in first })
        func rank(_ candidate: PlanningCandidate) -> Int {
            (baseScores[candidate.id] ?? 0) - (used.contains(candidate.id) ? 100 : 0) -
            cuisineCounts[candidate.cuisine, default: 0] * 3 - proteinCounts[families[candidate.id] ?? "Other", default: 0] * 6
        }
        for (dayIndex, day) in orderedDays.enumerated() {
            for meal in MealType.allCases where preferences.meals.contains(meal) {
                // Fill empty slots; an existing meal always wins, regardless of lock state.
                if baseline.contains(where: { $0.day == day && $0.meal == meal }) { continue }
                if preferences.useLeftovers, meal == .lunch, dayIndex > 0, dayIndex % 2 == 1,
                   let dinnerIndex = draft.firstIndex(where: { $0.day == orderedDays[dayIndex - 1] && $0.meal == .dinner }),
                   let note = draft[dinnerIndex].recipeSnapshot, note.canScaleQuantities {
                    let dinner = draft[dinnerIndex]
                    let lunchServings = Double(preferences.householdSize)
                    draft[dinnerIndex].preparedServings = dinner.servings + lunchServings
                    draft.append(PlannedMeal(day: day, meal: .lunch, recipeID: note.id, recipeTitle: note.title,
                        servings: lunchServings, recipeSnapshot: note, notes: "Reserved from the previous dinner. Verify cooling and storage before eating.", leftoversFromID: dinner.id))
                    continue
                }
                let matching = candidates.filter { $0.note.mealType == meal || ($0.note.mealType == .other && (meal == .lunch || meal == .dinner)) }
                guard let choice = matching.max(by: { first, second in
                    let a = rank(first)
                    let b = rank(second)
                    return a == b ? first.id.uuidString > second.id.uuidString : a < b
                }) else { throw MealPlanningError.noCandidates(meal) }
                let note = choice.note
                draft.append(PlannedMeal(day: day, meal: meal, recipeID: note.id,
                    recipeTitle: String((note.title.isEmpty ? "Untitled recipe" : note.title).prefix(500)),
                    servings: Double(preferences.householdSize), recipeSnapshot: note))
                used.insert(note.id)
                cuisineCounts[choice.cuisine, default: 0] += 1
                proteinCounts[families[choice.id] ?? "Other", default: 0] += 1
            }
        }
        try validateDraft(draft, days: Set(days), candidates: candidates, preferences: preferences, occupied: baseline)
        return MealPlanDraft(entries: draft,
            explanation: "A varied draft for \(preferences.householdSize) people, filling \(draft.count) empty meal slots. Existing meals are preserved. Ingredient variety guides selection; no calorie target or restrictive diet is imposed.",
            prepNotes: ["Review each original recipe for current directions, amounts, and serving yield.",
                        "Group vegetable washing and chopping before your busiest cooking days.",
                        "Cook whole grains and beans in batches when the selected recipes allow it.",
                        "Keep reserved leftovers separate, refrigerate promptly, and verify safe storage before reuse."],
            baseline: baseline, days: Set(days), preferences: preferences)
    }

    static func validateDraft(_ entries: [PlannedMeal], days: Set<String>, candidates: [PlanningCandidate], preferences: PlanningPreferences, occupied: [PlannedMeal]) throws {
        try preferences.validate()
        guard (1...14).contains(days.count), days.allSatisfy({ MealPlanDate.date($0) != nil }) else { throw MealPlanningError.invalidDraft }
        let lookup = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var slots = Set<String>()
        let occupiedSlots = Set(occupied.map { slot($0.day, $0.meal) })
        guard entries.count <= days.count * preferences.meals.count, Set(entries.map(\.id)).count == entries.count else { throw MealPlanningError.invalidDraft }
        for entry in entries {
            guard days.contains(entry.day), preferences.meals.contains(entry.meal),
                  entry.servings.isFinite, (0.25...24).contains(entry.servings),
                  slots.insert(slot(entry.day, entry.meal)).inserted,
                  !occupiedSlots.contains(slot(entry.day, entry.meal)),
                  let candidate = lookup[entry.recipeID],
                  candidate.note.mealType == entry.meal || (candidate.note.mealType == .other && [.lunch, .dinner].contains(entry.meal)) || entry.leftoversFromID != nil,
                  !candidate.note.ingredients.isEmpty, preferences.allowUnknownTimes || candidate.minutes != nil,
                  candidate.minutes == nil || (candidate.minutes! > 0 && candidate.minutes! <= preferences.maxCookingMinutes),
                  !IngredientExclusions.matches(candidate.note.ingredients, excluded: preferences.avoidIngredients) else { throw MealPlanningError.invalidDraft }
            if let parent = entry.leftoversFromID {
                guard let source = entries.first(where: { $0.id == parent }), source.recipeID == entry.recipeID,
                      source.meal == .dinner, entry.meal == .lunch, preferences.useLeftovers,
                      source.day < entry.day, let sourceDay = MealPlanDate.date(source.day), let targetDay = MealPlanDate.date(entry.day),
                      Calendar(identifier: .gregorian).dateComponents([.day], from: sourceDay, to: targetDay).day == 1,
                      candidate.note.canScaleQuantities,
                      (source.preparedServings ?? 0) >= source.servings + entry.servings else { throw MealPlanningError.invalidDraft }
            }
        }
        let expectedSlots = Set(days.flatMap { day in preferences.meals.map { slot(day, $0) } }).subtracting(occupiedSlots)
        guard slots == expectedSlots else { throw MealPlanningError.invalidDraft }
    }

    static func resolve(_ meal: PlannedMeal, personal: [CookingNote], bank: [BankRecipe]) -> CookingNote? {
        personal.first { $0.id == meal.recipeID } ?? meal.recipeSnapshot ?? bank.first { $0.id == meal.recipeID }?.note()
    }

    static func slot(_ day: String, _ meal: MealType) -> String { day + "/" + meal.rawValue }

    private static func score(_ candidate: PlanningCandidate, preferences: PlanningPreferences) -> Int {
        let groups = candidate.foodGroups
        var result = (groups.contains("Vegetables") ? 12 : 0) + (groups.contains("Whole grains") ? 8 : 0) + (groups.contains("Beans & lentils") ? 8 : 0)
        result += candidate.note.isFavorite ? 4 : 0
        result += candidate.note.rating
        result += min(12, preferences.pantryItems.filter { item in candidate.note.ingredients.contains { RecipeIngredientIdentity.contains($0, term: item) } }.count * 3)
        if preferences.preferredCuisines.contains(candidate.cuisine) { result += 5 }
        if preferences.budgetMindful && groups.contains("Beans & lentils") { result += 3 }
        return result
    }
}

enum IngredientExclusions {
    private static let aliases: [String: [String]] = [
        "dairy": ["milk", "cheese", "butter", "cream", "yogurt", "yoghurt", "whey", "casein", "kefir"],
        "milk": ["milk", "cheese", "butter", "cream", "yogurt", "yoghurt", "whey", "casein"],
        "egg": ["egg", "eggs", "mayonnaise", "albumen"],
        "eggs": ["egg", "eggs", "mayonnaise", "albumen"],
        "wheat": ["wheat", "flour", "semolina", "bulgur", "couscous", "spelt", "farro", "bread", "pasta"],
        "gluten": ["wheat", "flour", "semolina", "bulgur", "couscous", "spelt", "farro", "barley", "rye", "bread", "pasta"],
        "nuts": ["almond", "walnut", "pecan", "cashew", "pistachio", "hazelnut", "macadamia", "peanut"],
        "tree nuts": ["almond", "walnut", "pecan", "cashew", "pistachio", "hazelnut", "macadamia"],
        "peanut": ["peanut", "groundnut"], "peanuts": ["peanut", "groundnut"],
        "soy": ["soy", "soya", "tofu", "tempeh", "edamame", "miso"],
        "fish": ["fish", "salmon", "tuna", "cod", "sardine", "anchovy", "trout", "haddock", "halibut"],
        "shellfish": ["shrimp", "prawn", "crab", "lobster", "mussel", "clam", "oyster", "scallop"],
        "sesame": ["sesame", "tahini"]
    ]
    static func matches(_ ingredients: [String], excluded: [String]) -> Bool {
        if !excluded.isEmpty && ingredients.isEmpty { return true }
        return excluded.contains { term in
            let normalized = RecipeIngredientIdentity.key(term)
            let words = aliases[normalized] ?? [normalized]
            return ingredients.contains { line in words.contains { RecipeIngredientIdentity.contains(line, term: $0) } }
        }
    }
}

enum RecipeFoodGroups {
    private static let groups: [(String, [String])] = [
        ("Vegetables", ["spinach", "kale", "broccoli", "carrot", "cabbage", "tomato", "zucchini", "courgette", "eggplant", "aubergine", "squash", "cauliflower", "bell pepper", "mushroom", "lettuce", "cucumber", "asparagus"]),
        ("Fruit", ["apple", "pear", "banana", "blueberry", "blueberries", "strawberry", "strawberries", "peach", "mango", "pineapple", "orange", "avocado"]),
        ("Whole grains", ["brown rice", "wild rice", "whole wheat", "whole-wheat", "wholemeal", "whole grain", "quinoa", "bulgur", "barley", "farro", "oats", "oatmeal", "buckwheat"]),
        ("Beans & lentils", ["lentil", "chickpea", "garbanzo", "black bean", "kidney bean", "cannellini", "pinto bean", "edamame", "tofu", "tempeh"]),
        ("Protein foods", ["lentil", "chickpea", "bean", "tofu", "tempeh", "chicken", "turkey", "salmon", "tuna", "cod", "shrimp", "prawn", "egg", "lean beef"]),
        ("Nuts & seeds", ["walnut", "almond", "peanut", "cashew", "pumpkin seed", "sunflower seed", "sesame", "chia", "flax"])
    ]
    static func infer(_ ingredients: [String]) -> [String] {
        groups.compactMap { name, words in ingredients.contains { line in words.contains { RecipeIngredientIdentity.contains(line, term: $0) } } ? name : nil }
    }
    static func proteinFamily(_ ingredients: [String]) -> String {
        for (name, words) in [("Legumes", ["lentil", "chickpea", "bean", "tofu", "tempeh"]), ("Fish", ["fish", "salmon", "tuna", "cod", "shrimp"]), ("Poultry", ["chicken", "turkey"]), ("Eggs", ["egg"]), ("Meat", ["beef", "pork", "lamb"])] {
            if ingredients.contains(where: { line in words.contains { RecipeIngredientIdentity.contains(line, term: $0) } }) { return name }
        }
        return "Other"
    }
}

struct GroceryItem: Identifiable, Equatable {
    let id: String
    var ingredient: String
    var amount: Double?
    var unit: String
    var originalLines: [String]
    var mealTitles: Set<String>
    var needsSourceCheck: Bool
    var displayAmount: String {
        if let amount { return RecipeQuantity.format(amount) + (unit.isEmpty ? "" : " " + unit) }
        return "Check recipe amount"
    }
}

enum MealPlanGroceries {
    static func build(entries: [PlannedMeal], personal: [CookingNote], bank: [BankRecipe], pantry: [String]) -> [GroceryItem] {
        var items: [String: GroceryItem] = [:]
        for meal in entries where meal.leftoversFromID == nil {
            guard let note = MealPlanningEngine.resolve(meal, personal: personal, bank: bank) else { continue }
            let portions = meal.preparedServings ?? meal.servings
            let factor = portions / Double(max(1, note.servings))
            for raw in note.ingredients {
                let scaled = note.canScaleQuantities ? RecipeQuantity.scale(raw, by: factor) : raw
                let parsed = parse(scaled)
                let ingredient = parsed?.ingredient ?? scaled
                if pantry.contains(where: { RecipeIngredientIdentity.contains(ingredient, term: $0) }) { continue }
                let uncertain = !note.canScaleQuantities || parsed == nil
                let key = uncertain ? "raw|" + RecipeIngredientIdentity.key(ingredient) + "|" + (note.canScaleQuantities ? "known" : "unknown") : "amount|" + RecipeIngredientIdentity.key(ingredient) + "|" + parsed!.unit
                if var item = items[key] {
                    if let amount = item.amount, let addition = parsed?.amount, !uncertain { item.amount = amount + addition }
                    if !item.originalLines.contains(raw) { item.originalLines.append(raw) }
                    item.mealTitles.insert(meal.recipeTitle)
                    items[key] = item
                } else {
                    items[key] = GroceryItem(id: key, ingredient: ingredient, amount: uncertain ? nil : parsed?.amount,
                        unit: parsed?.unit ?? "", originalLines: [raw], mealTitles: [meal.recipeTitle], needsSourceCheck: uncertain)
                }
            }
        }
        return items.values.sorted { $0.ingredient.localizedStandardCompare($1.ingredient) == .orderedAscending }
    }

    private static func parse(_ line: String) -> (amount: Double, unit: String, ingredient: String)? {
        guard let value = RecipeQuantity.leadingQuantity(in: line), value.quantity > 0 else { return nil }
        let words = value.suffix.split(separator: " ", maxSplits: 1).map(String.init)
        guard let first = words.first, !first.isEmpty, !first.hasPrefix("("), !first.contains("/") else { return nil }
        let units: [String: (KitchenUnit, String)] = ["g": (.grams, "g"), "grams": (.grams, "g"), "gram": (.grams, "g"),
            "kg": (.kilograms, "g"), "kilograms": (.kilograms, "g"), "lb": (.pounds, "g"), "lbs": (.pounds, "g"), "pound": (.pounds, "g"), "pounds": (.pounds, "g"), "oz": (.ounces, "g"), "ounce": (.ounces, "g"), "ounces": (.ounces, "g"),
            "ml": (.millilitres, "mL"), "millilitres": (.millilitres, "mL"), "l": (.litres, "mL"), "litres": (.litres, "mL")]
        if let (source, label) = units[first.lowercased()], words.count == 2,
           let amount = KitchenUnit.convert(value.quantity, from: source, to: label == "g" ? .grams : .millilitres) {
            return (amount, label, words[1])
        }
        let simpleUnits = ["cup": "cups", "cups": "cups", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp", "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp", "can": "cans", "cans": "cans", "clove": "cloves", "cloves": "cloves", "bunch": "bunches", "bunches": "bunches"]
        if let unit = simpleUnits[first.lowercased()], words.count == 2 { return (value.quantity, unit, words[1]) }
        // Unrecognized measurement units remain raw; never invent a density or
        // misinterpret package amounts as counts of the ingredient itself.
        if ["fluid", "fl", "us", "uk", "imperial", "pinch", "pinches", "dash", "dashes", "package", "packages", "packet", "packets", "stick", "sticks", "x", "quart", "quarts", "pint", "pints", "gallon", "gallons", "oz.", "lb.", "tbs", "tbs.", "tbsp.", "tsp.", "dozen"].contains(first.lowercased()) { return nil }
        return (value.quantity, "", value.suffix)
    }
}
