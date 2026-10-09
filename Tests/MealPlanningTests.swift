import Foundation

final class PlannerURLProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var captured: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured = request
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct MealPlanningTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ result: Bool, _ name: String) { checks += 1; if !result { fatalError("FAIL: \(name)") } }
        func rejects(_ name: String, _ operation: () throws -> Void) { do { try operation(); check(false, name) } catch { check(true, name) } }
        let bankURL = URL(fileURLWithPath: "CookOut/Resources/recipe-bank.json")
        let catalog = try RecipeBankCatalog.decode(Data(contentsOf: bankURL))
        check(catalog.recipes.count >= 5000, "at least 5000 real distinct records")
        check(Set(catalog.recipes.map(\.sourceURL)).count == catalog.recipes.count, "unique source links")
        check(Set(catalog.recipes.map(\.id)).count == catalog.recipes.count, "unique stable recipe IDs")
        check(catalog.attribution.contains("CC BY 3.0"), "licensed attribution")
        check(catalog.recipes.allSatisfy { $0.note().steps.isEmpty }, "no copied publisher directions")
        check(catalog.recipes.filter { $0.foodGroups.contains("Vegetables") }.count > 3500, "produce-rich selection")
        check(catalog.recipes.filter { $0.foodGroups.contains("Whole grains") }.count > 1000, "whole grains included")
        check(catalog.recipes.filter { $0.foodGroups.contains("Beans & lentils") }.count > 1500, "legumes included")
        check(catalog.recipes.allSatisfy { $0.title.range(of: "\\b(keto|paleo|detox|atkins)\\b", options: [.regularExpression, .caseInsensitive]) == nil }, "restrictive titles excluded")
        let store = RecipeBankStore(catalogURL: bankURL)
        check(store.errorMessage == nil && store.recipes.count == catalog.recipes.count, "bank loads")
        check(!store.search(query: "lentil").isEmpty, "ingredient search")
        check(store.search(query: "", meal: .breakfast, maxMinutes: 30).allSatisfy { $0.mealType == .breakfast && $0.totalMinutes! <= 30 }, "meal and cooking time filter")
        check(store.search(query: "", cuisine: "Indian").allSatisfy { $0.cuisine == "Indian" }, "cuisine filter")
        check(store.search(query: "", group: "Whole grains").allSatisfy { $0.foodGroups.contains("Whole grains") }, "ingredient-group filter")
        let missing = RecipeBankStore(catalogURL: URL(fileURLWithPath: "/tmp/CookOut-no-such-catalog"))
        check(missing.recipes.isEmpty && missing.errorMessage != nil, "missing bank fails independently")
        let unknown = catalog.recipes.first { $0.servings == nil }!.note()
        check(!unknown.canScaleQuantities, "unknown yield cannot scale")
        var confirmed = unknown; confirmed.sourceYieldIsServings = true
        check(confirmed.canScaleQuantities, "explicit user confirmation enables scaling")
        check(try JSONDecoder().decode(CookingNote.self, from: JSONEncoder().encode(confirmed)) == confirmed, "source provenance round trip")
        for url in ["http://example.com/a", "file:///tmp/x", "https://user:password@example.com/a", "https://localhost/a", "https://127.0.0.1/a", "https://example.com:999/a"] { check(RecipeSourceURL.valid(url) == nil, "unsafe URL rejected") }
        check(RecipeSourceURL.valid("https://example.com/recipe") != nil, "HTTPS source accepted")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: bankURL)) as! [String: Any]
        object["version"] = 9
        rejects("unknown bank schema") { _ = try RecipeBankCatalog.decode(JSONSerialization.data(withJSONObject: object)) }
        object["version"] = 1
        var records = object["recipes"] as! [[String: Any]]; records[1] = records[0]; object["recipes"] = records
        rejects("duplicate bank records") { _ = try RecipeBankCatalog.decode(JSONSerialization.data(withJSONObject: object)) }
        check(!IngredientExclusions.matches(["1 eggplant", "nutmeg"], excluded: ["eggs", "nuts"]), "whole-word exclusions avoid unrelated foods")
        check(IngredientExclusions.matches(["2 tbsp tahini"], excluded: ["sesame"]), "allergen aliases")
        check(IngredientExclusions.matches(["1 cup walnuts"], excluded: ["tree nuts"]), "plural allergen matching")
        check(IngredientExclusions.matches([], excluded: ["peanuts"]), "missing ingredients cannot establish exclusion")
        check(!RecipeFoodGroups.infer(["eggplant"]).contains("Protein foods"), "eggplant is not eggs")
        var prefs = PlanningPreferences()
        let days = (0..<7).map { String(format: "2026-10-%02d", 12 + $0) }
        var badPrefs = prefs; badPrefs.householdSize = 0
        rejects("invalid household") { try badPrefs.validate() }
        badPrefs = prefs; badPrefs.meals = [.dinner, .dinner]
        rejects("duplicate meal preferences") { try badPrefs.validate() }
        badPrefs = prefs; badPrefs.avoidIngredients = [""]
        rejects("empty exclusion") { try badPrefs.validate() }
        prefs.avoidIngredients = ["peanuts"]
        let candidateStart = Date()
        let candidates = MealPlanningEngine.candidates(personal: [], bank: catalog.recipes, preferences: prefs)
        FileHandle.standardOutput.write(Data("Candidate preparation: \(String(format: "%.2f", Date().timeIntervalSince(candidateStart)))s for \(catalog.recipes.count) recipes\n".utf8))
        let generationStart = Date()
        check(!candidates.isEmpty && candidates.allSatisfy { $0.minutes != nil && $0.minutes! <= prefs.maxCookingMinutes }, "time-bound candidates")
        check(candidates.allSatisfy { !IngredientExclusions.matches($0.note.ingredients, excluded: prefs.avoidIngredients) }, "excluded ingredients filtered")
        let generated = try MealPlanningEngine.generate(days: days, existing: [], candidates: candidates, preferences: prefs)
        FileHandle.standardOutput.write(Data("Local week generation: \(String(format: "%.2f", Date().timeIntervalSince(generationStart)))s\n".utf8))
        check(generated.entries.count == 21, "complete week across three meals")
        try MealPlanningEngine.validateDraft(generated.entries, days: Set(days), candidates: candidates, preferences: prefs, occupied: [])
        check(true, "local draft semantically valid")
        let leftovers = generated.entries.filter { $0.leftoversFromID != nil }
        check(leftovers.count > 0, "known-yield dinners reserve next-day lunches")
        check(leftovers.allSatisfy { child in generated.entries.first { $0.id == child.leftoversFromID }!.preparedServings == 4 }, "extra dinner portions accounted for")
        check(Set(generated.entries.filter { $0.leftoversFromID == nil }.map(\.recipeID)).count == generated.entries.count - leftovers.count, "variety without unintentional repeats")
        var fixed = generated.entries[0]; fixed.isLocked = true
        let preserved = try MealPlanningEngine.generate(days: days, existing: [fixed], candidates: candidates, preferences: prefs)
        check(preserved.entries.count == 20 && !preserved.entries.contains { $0.day == fixed.day && $0.meal == fixed.meal }, "locked/existing meals preserved")
        rejects("incomplete draft rejected") { try MealPlanningEngine.validateDraft(Array(generated.entries.dropLast()), days: Set(days), candidates: candidates, preferences: prefs, occupied: []) }
        var malformed = generated.entries; malformed[1].day = "2026-10-99"
        rejects("out-of-week date rejected") { try MealPlanningEngine.validateDraft(malformed, days: Set(days), candidates: candidates, preferences: prefs, occupied: []) }
        malformed = generated.entries; malformed[1].day = malformed[0].day; malformed[1].meal = malformed[0].meal
        rejects("duplicate slot rejected") { try MealPlanningEngine.validateDraft(malformed, days: Set(days), candidates: candidates, preferences: prefs, occupied: []) }
        malformed = generated.entries; malformed[0].recipeID = UUID()
        rejects("invented recipe ID rejected") { try MealPlanningEngine.validateDraft(malformed, days: Set(days), candidates: candidates, preferences: prefs, occupied: []) }
        rejects("no suitable candidates") { _ = try MealPlanningEngine.generate(days: days, existing: [], candidates: [], preferences: prefs) }
        var n = CookingNote(title: "Rice and lentils", ingredients: ["100 g brown rice", "1 cup lentils", "salt to taste"], servings: 2, prepMinutes: 10, cookMinutes: 20, mealType: .dinner)
        let first = PlannedMeal(day: days[0], meal: .dinner, recipeID: n.id, recipeTitle: n.title, servings: 2, recipeSnapshot: n, preparedServings: 4)
        let child = PlannedMeal(day: days[1], meal: .lunch, recipeID: n.id, recipeTitle: n.title, servings: 2, recipeSnapshot: n, leftoversFromID: first.id)
        let groceries = MealPlanGroceries.build(entries: [first, child], personal: [], bank: [], pantry: [])
        check(groceries.first { $0.ingredient == "brown rice" }?.amount == 200, "leftover portions scaled once, not twice")
        check(groceries.first { $0.ingredient == "lentils" }?.amount == 2, "cup quantities scaled")
        check(groceries.first { $0.ingredient == "salt to taste" }?.needsSourceCheck == true, "unquantified amounts stay uncertain")
        check(!MealPlanGroceries.build(entries: [first, child], personal: [], bank: [], pantry: ["rice"]).contains { $0.ingredient == "brown rice" }, "pantry items removed from shopping")
        var n2 = n; n2.id = UUID(); n2.ingredients = ["0.2 kg brown rice"]
        let second = PlannedMeal(day: days[2], meal: .dinner, recipeID: n2.id, recipeTitle: n2.title, servings: 2, recipeSnapshot: n2)
        check(MealPlanGroceries.build(entries: [first, second], personal: [], bank: [], pantry: []).first { $0.ingredient == "brown rice" }?.amount == 400, "weight units aggregate exactly")
        n.sourceURL = "https://example.com/recipe"; n.sourceYieldIsServings = false
        let unscaled = PlannedMeal(day: days[0], meal: .dinner, recipeID: n.id, recipeTitle: n.title, servings: 6, recipeSnapshot: n)
        check(MealPlanGroceries.build(entries: [unscaled], personal: [], bank: [], pantry: []).allSatisfy { $0.amount == nil && $0.needsSourceCheck }, "unknown yield does not invent grocery quantities")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CookOut-advanced-tests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plan.json")
        let plans = MealPlanStore(fileURL: url)
        check(plans.savePreferences(prefs), "preferences persisted")
        check(plans.apply(generated), "full draft applied atomically")
        let restarted = MealPlanStore(fileURL: url)
        check(restarted.prepNotesByWeek[days[0]] == generated.prepNotes, "preparation outline survives restart")
        check(restarted.entries == plans.entries && restarted.preferences == prefs, "restart keeps snapshots and preferences")
        check(restarted.toggleGrocery("2026-10-12|rice|200g"), "grocery checkbox saved")
        check(MealPlanStore(fileURL: url).checkedGroceryKeys.contains("2026-10-12|rice|200g"), "grocery checkbox survives restart")
        check(plans.setLocked(first.id, locked: true), "missing lock ID is safe no-op")
        let entry = plans.entries[0]
        check(plans.setLocked(entry.id, locked: true), "meal locked")
        var changed = entry; changed.recipeTitle = "Changed"
        check(!plans.save(changed), "locked meal cannot be replaced")
        check(!plans.remove(entry), "locked meal cannot be deleted")
        check(!plans.move(entry, to: days[6], mealType: .snack), "locked meal cannot be moved")
        check(plans.setCompleted(entry.id, completed: true), "locked meal can be marked cooked")
        check(plans.setLocked(entry.id, locked: false), "unlock meal")
        check(plans.copyWeek(from: days), "copy week preserves linked leftovers")
        check(!plans.copyWeek(from: days), "copy refuses occupied week atomically")
        check(plans.entries.count == 42, "failed copy adds no partial entries")
        let staleURL = dir.appendingPathComponent("stale.json")
        let stale = MealPlanStore(fileURL: staleURL)
        check(stale.savePreferences(prefs), "stale test preferences")
        let parallel = MealPlanStore(fileURL: staleURL)
        check(parallel.save(fixed), "concurrent edit saves")
        check(!stale.apply(generated), "draft rejects a concurrent week change")
        check(MealPlanStore(fileURL: staleURL).entries == [fixed], "concurrent change retained")
        let failingURL = dir.appendingPathComponent("failure.json")
        let failure = MealPlanStore(fileURL: failingURL, writeData: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        check(!failure.apply(try MealPlanningEngine.generate(days: days, existing: [], candidates: candidates, preferences: PlanningPreferences())), "failed atomic write rejected")
        check(failure.entries.isEmpty && !FileManager.default.fileExists(atPath: failingURL.path), "failed write leaves state untouched")
        let corrupt = dir.appendingPathComponent("bad.json"); let badBytes = Data("{not json}".utf8); try badBytes.write(to: corrupt)
        let unavailable = MealPlanStore(fileURL: corrupt)
        check(!unavailable.isAvailable && !unavailable.save(entry), "malformed state disables mutations")
        check(try Data(contentsOf: corrupt) == badBytes, "malformed file preserved")
        let context = try CookingAssistantPolicy.context(cookbook: [n], folders: [], bank: catalog.recipes, query: "enhance lentil rice")
        check(context.contains(n.id.uuidString), "assistant receives exact personal IDs")
        check(CookingAssistantPolicy.foundation.contains("Do not impose keto"), "nonrestrictive specialist policy")
        check(CookingAssistantFocus.enhance.instruction.contains("texture"), "enhancement focus")
        check(CookingAssistantFocus.brainstorm.instruction.contains("original"), "brainstorm labels original ideas")
        let short = GroqMealPlanService.shortlist(candidates, preferences: prefs)
        let requestData = try GroqMealPlanService.payload(days: days, existing: [], candidates: short, preferences: prefs)
        let payload = try JSONSerialization.jsonObject(with: requestData) as! [String: Any]
        check(payload["model"] as? String == "openai/gpt-oss-120b", "planner uses 120B")
        check(payload["reasoning_effort"] as? String == "medium" && payload["reasoning_format"] == nil, "supported GPT OSS reasoning request")
        let responseFormat = payload["response_format"] as! [String: Any]
        check((responseFormat["json_schema"] as! [String: Any])["strict"] as? Bool == true, "strict structured output")
        let draftForMock = try MealPlanningEngine.generate(days: days, existing: [], candidates: short, preferences: prefs)
        let meals: [[String: Any]] = draftForMock.entries.map { ["day": $0.day, "meal": $0.meal.rawValue, "recipe_id": $0.recipeID.uuidString, "servings": $0.servings, "notes": "Prepare and check the source."] }
        func response(_ meals: [[String: Any]], finish: String = "stop", refusal: String? = nil) throws -> Data {
            let content = String(decoding: try JSONSerialization.data(withJSONObject: ["explanation": "A varied week.", "prep_notes": ["Wash produce."], "meals": meals]), as: UTF8.self)
            var message: [String: Any] = ["content": content]; if let refusal { message["refusal"] = refusal }
            return try JSONSerialization.data(withJSONObject: ["choices": [["message": message, "finish_reason": finish]]])
        }
        let valid = try response(meals)
        let decoded = try GroqMealPlanService.decode(valid, days: Set(days), existing: [], candidates: short, preferences: prefs)
        check(decoded.entries.count == 21 && decoded.entries.allSatisfy { $0.recipeSnapshot != nil }, "structured plan resolves only trusted candidates")
        rejects("truncated model response") { _ = try GroqMealPlanService.decode(response(meals, finish: "length"), days: Set(days), existing: [], candidates: short, preferences: prefs) }
        rejects("model refusal") { _ = try GroqMealPlanService.decode(response(meals, refusal: "Unable"), days: Set(days), existing: [], candidates: short, preferences: prefs) }
        rejects("incomplete model response") { _ = try GroqMealPlanService.decode(response(Array(meals.dropLast())), days: Set(days), existing: [], candidates: short, preferences: prefs) }
        var invented = meals; invented[0]["recipe_id"] = UUID().uuidString
        rejects("invented model ID") { _ = try GroqMealPlanService.decode(response(invented), days: Set(days), existing: [], candidates: short, preferences: prefs) }
        var wrong = meals; wrong[0]["servings"] = 999
        rejects("model ignores household size") { _ = try GroqMealPlanService.decode(response(wrong), days: Set(days), existing: [], candidates: short, preferences: prefs) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PlannerURLProtocol.self]
        let service = GroqMealPlanService(session: URLSession(configuration: config))
        PlannerURLProtocol.status = 200; PlannerURLProtocol.body = valid
        let viaHTTP = try await service.draft(days: days, existing: [], candidates: candidates, preferences: prefs, apiKey: "synthetic-test-key")
        check(viaHTTP.entries.count == 21 && PlannerURLProtocol.captured?.httpMethod == "POST", "HTTP integration passes structured draft")
        for status in [401, 429, 500] {
            PlannerURLProtocol.status = status
            do { _ = try await service.draft(days: days, existing: [], candidates: candidates, preferences: prefs, apiKey: "synthetic-test-key"); check(false, "HTTP failure \(status)") } catch { check(true, "HTTP failure \(status) leaves plan unchanged") }
        }
        PlannerURLProtocol.status = 200; PlannerURLProtocol.body = Data("not json".utf8)
        do { _ = try await service.draft(days: days, existing: [], candidates: candidates, preferences: prefs, apiKey: "synthetic-test-key"); check(false, "malformed HTTP") } catch { check(true, "malformed HTTP response rejected") }
        print("PASS: \(checks) advanced meal-planning checks")
    }
}
