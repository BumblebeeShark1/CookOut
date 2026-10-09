import Foundation

@main
struct RecipeToolsTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            guard condition else { fatalError("FAIL: \(name)") }
        }
        func close(_ value: Double?, _ expected: Double, _ name: String) {
            check(value != nil && abs(value! - expected) < max(0.0000001, abs(expected) * 1e-10), name)
        }
        let scaling: [(String, Double, String)] = [
            ("1 cup flour", 2, "2 cup flour"), ("2 eggs", 0.5, "1 eggs"),
            ("1/2 tsp salt", 2, "1 tsp salt"), ("1 1/2 cups flour", 2, "3 cups flour"),
            ("1½ cups milk", 0.5, "¾ cups milk"), ("½ cup milk", 0.5, "¼ cup milk"),
            ("⅓ cup sugar", 2, "⅔ cup sugar"), (".5 tsp salt", 2, "1 tsp salt"),
            ("1.25 L water", 2, "2 ½ L water"), ("250g flour", 0.5, "125g flour"),
            ("1–2 tbsp oil", 2, "2–4 tbsp oil"), ("1 to 2 tbsp oil", 0.5, "½ to 1 tbsp oil"),
            ("2 (400 g) cans tomatoes", 2, "4 (400 g) cans tomatoes"),
            ("2 x 400 g cans tomatoes", 0.5, "1 x 400 g cans tomatoes"),
            ("salt to taste", 2, "salt to taste"), ("a pinch of salt", 2, "a pinch of salt"),
            ("1/0 cup", 2, "1/0 cup"), ("1//2 cup", 2, "1//2 cup"),
            ("1 1//2 cups", 2, "1 1//2 cups"), ("1 to", 2, "1 to"),
            ("2-1 tbsp", 2, "2-1 tbsp"), ("1-foo eggs", 2, "1-foo eggs"),
            ("1.2.3 cups", 2, "1.2.3 cups"), ("1st ingredient", 2, "1st ingredient"),
            ("1 cup", .nan, "1 cup"), ("1 cup", -2, "1 cup"), ("1 cup", 0, "1 cup"),
            ("1 cup", 1001, "1 cup"), ("1/2 cup", 1, "1/2 cup")
        ]
        for (input, factor, expected) in scaling { check(RecipeQuantity.scale(input, by: factor) == expected, "scale \(input) by \(factor)") }
        check(RecipeQuantity.ingredientLines("1 cup flour\n2 eggs\n• ½ tsp salt\n- 250g milk\n\n") == ["1 cup flour", "2 eggs", "½ tsp salt", "250g milk"], "ingredient quantities survive editor parsing")
        check(RecipeQuantity.directionLines("1. Preheat to 180°C\n2) Bake for 20 minutes\n• Cool") == ["Preheat to 180°C", "Bake for 20 minutes", "Cool"], "numbered directions")
        check(!RecipeQuantity.canScale("salt to taste"), "unquantified ingredient")
        check(RecipeQuantity.canScale("½ tsp"), "fraction recognized")
        check(RecipeQuantity.scale(String(repeating: "1", count: 10001), by: 2).count == 10001, "oversized input preserved")
        check(RecipeQuantity.format(0.00000001) != "0", "tiny amounts retain quantity")
        close(KitchenUnit.convert(1, from: .pounds, to: .grams), 453.59237, "pounds to grams")
        close(KitchenUnit.convert(1, from: .ounces, to: .grams), 28.349523125, "ounces to grams")
        close(KitchenUnit.convert(1, from: .cups, to: .millilitres), 236.5882365, "US cup")
        close(KitchenUnit.convert(1, from: .tablespoons, to: .teaspoons), 3, "spoons")
        close(KitchenUnit.convert(1, from: .imperialPints, to: .millilitres), 568.26125, "UK pint")
        close(KitchenUnit.convert(1, from: .imperialPints, to: .imperialOunces), 20, "UK pint to UK fluid ounce")
        close(KitchenUnit.convert(1, from: .usPints, to: .millilitres), 473.176473, "US pint differs")
        close(KitchenUnit.convert(180, from: .celsius, to: .fahrenheit), 356, "oven temperature")
        close(KitchenUnit.convert(32, from: .fahrenheit, to: .celsius), 0, "freezing point")
        close(KitchenUnit.convert(-459.67, from: .fahrenheit, to: .celsius), -273.15, "absolute zero in Fahrenheit")
        close(KitchenUnit.convert(-40, from: .celsius, to: .fahrenheit), -40, "negative temperature")
        check(KitchenUnit.convert(-274, from: .celsius, to: .fahrenheit) == nil, "absolute zero bound")
        check(KitchenUnit.convert(-1, from: .grams, to: .ounces) == nil, "negative mass rejected")
        check(KitchenUnit.convert(1, from: .grams, to: .cups) == nil, "no invented density")
        check(KitchenUnit.convert(.infinity, from: .grams, to: .ounces) == nil, "infinity rejected")
        for dimension in KitchenDimension.allCases {
            for from in dimension.units {
                for to in dimension.units {
                    let forward = KitchenUnit.convert(123.45, from: from, to: to)
                    close(forward.flatMap { KitchenUnit.convert($0, from: to, to: from) }, 123.45, "round trip \(from) / \(to)")
                }
            }
        }
        let recipeConversions: [(String, RecipeMeasurementSystem, String)] = [
            ("500 g flour", .usCustomary, "1.102 lb flour"),
            ("250 mL milk", .usCustomary, "1.057 US cups milk"),
            ("1 lb flour", .metric, "453.6 g flour"),
            ("1 US cup water", .metric, "236.6 mL water"),
            ("1½ tbsp oil", .metric, "22.18 mL oil"),
            ("1 UK pint milk", .metric, "568.3 mL milk"),
            ("1 imperial pint milk", .metric, "568.3 mL milk"),
            ("1 L stock", .ukImperial, "1.76 UK pints stock"),
            ("1-2 tbsp oil", .metric, "14.79-29.57 mL oil"),
            ("Bake at 200°C for 25 minutes.", .usCustomary, "Bake at 392 °F for 25 minutes."),
            ("Bake at 350 °F for 20 minutes.", .metric, "Bake at 176.7 °C for 20 minutes."),
            ("Freeze at -20°C.", .usCustomary, "Freeze at -4 °F."),
            ("Hold at -20–-10°C.", .usCustomary, "Hold at -4–14 °F."),
            ("Bake at 180℃", .usCustomary, "Bake at 356 °F"),
            ("2 (400 g) cans tomatoes", .usCustomary, "2 (14.11 oz) cans tomatoes"),
            ("1/0 cup oil", .metric, "1/0 cup oil"),
            ("-2 g flour", .usCustomary, "-2 g flour"),
            ("1.2.3 g sugar", .usCustomary, "1.2.3 g sugar"),
            ("2 eggs, salt to taste", .metric, "2 eggs, salt to taste"),
            ("500 g flour", .original, "500 g flour")
        ]
        for (input, system, expected) in recipeConversions { check(RecipeQuantity.convertMeasurements(in: input, to: system) == expected, "whole recipe conversion: \(input)") }
        let entireRecipe = "500 g flour\n250 mL milk\nBake at 200°C for 25 minutes.\nSalt to taste."
        check(RecipeQuantity.convertMeasurements(in: entireRecipe, to: .usCustomary) == "1.102 lb flour\n1.057 US cups milk\nBake at 392 °F for 25 minutes.\nSalt to taste.", "entire multiline recipe converted in one action")
        check(RecipeQuantity.convertMeasurements(in: RecipeQuantity.scale("250g flour", by: 2), to: .usCustomary) == "1.102 lb flour", "portion scaling composes with conversion")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CookOut-feature-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("meal-plan.json")
        let first = MealPlanStore(fileURL: url)
        check(first.isAvailable && first.entries.isEmpty, "new empty planner")
        check(!FileManager.default.fileExists(atPath: url.path), "loading does not create a plan")
        var meal = PlannedMeal(day: "2026-10-08", meal: .dinner, recipeID: UUID(), recipeTitle: "Soup", servings: 4)
        check(first.save(meal), "persist planned meal")
        let restarted = MealPlanStore(fileURL: url)
        check(restarted.entries == [meal], "restart restores meals")
        meal.servings = 2
        check(restarted.save(meal) && restarted.entries.count == 1, "edit replaces same ID")
        let second = PlannedMeal(day: "2026-10-09", meal: .lunch, recipeID: UUID(), recipeTitle: "Salad", servings: 1)
        check(first.save(second), "other window saves")
        check(first.entries.contains(meal) && first.entries.contains(second), "other window merges latest persisted edit")
        check(restarted.remove(meal) && restarted.entries == [second], "remove merges other window addition")
        let stable = try Data(contentsOf: url)
        let failedWriter = MealPlanStore(fileURL: url, writeData: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        check(!failedWriter.save(meal), "write error surfaced")
        check(failedWriter.entries == [second] && failedWriter.errorMessage != nil, "write error leaves memory unchanged")
        check(try Data(contentsOf: url) == stable, "write error leaves disk unchanged")
        var invalid = meal; invalid.servings = -1
        check(!first.save(invalid), "invalid servings rejected")
        check(try Data(contentsOf: url) == stable, "invalid mutation leaves disk unchanged")
        for bad in ["2026-02-30", "2026-13-01", "2026-00-10", "2026-10-00", "2026-1-01", "not a date"] { check(MealPlanDate.date(bad) == nil, "invalid calendar date \(bad)") }
        check(MealPlanDate.date("2024-02-29") != nil, "leap day valid")
        check(MealPlanDate.date("2025-02-29") == nil, "non leap day rejected")
        let corrupt = Data("{broken json".utf8)
        try corrupt.write(to: url)
        first.reload()
        check(!first.isAvailable && first.errorMessage != nil, "corruption blocks editing")
        check(!first.save(meal), "corrupt planner remains read only")
        check(try Data(contentsOf: url) == corrupt, "corrupt file never overwritten")
        try stable.write(to: url)
        first.reload()
        check(first.isAvailable && first.entries == [second], "reload recovers after repaired storage")
        let corruptions: [MealPlanDocument] = [MealPlanDocument(version: 99, entries: [meal]), MealPlanDocument(entries: [meal, meal]), MealPlanDocument(entries: [invalid])]
        for document in corruptions {
            let data = try JSONEncoder().encode(document); try data.write(to: url)
            let store = MealPlanStore(fileURL: url)
            check(!store.isAvailable && !store.save(second), "invalid document rejected")
            check(try Data(contentsOf: url) == data, "invalid document preserved")
        }
        print("PASS: \(checks) checks for scaling, conversions, editor quantities, planner persistence, restart, merging, malformed state, and write failure.")
    }
}
