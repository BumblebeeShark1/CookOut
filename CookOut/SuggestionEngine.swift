import Foundation
import CoreML

struct CookingSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let insertion: String
    let symbol: String
}

protocol CookingSuggestionEngine {
    func suggestions(title: String, body: String) async -> [CookingSuggestion]
}

struct LocalCookingSuggestionEngine: CookingSuggestionEngine {
    func suggestions(title: String, body: String) async -> [CookingSuggestion] {
        let text = (title + " " + body).lowercased()
        var results: [CookingSuggestion] = []
        if !text.contains("salt") {
            results.append(.init(title: "Season in layers", insertion: "\nTaste, then add salt a little at a time.", symbol: "sparkles"))
        }
        if text.contains("chicken") || text.contains("meat") {
            results.append(.init(title: "Add temperature", insertion: "\nTarget internal temperature: ___°F", symbol: "thermometer.medium"))
        }
        if text.contains("bake") || text.contains("oven") {
            results.append(.init(title: "Record oven details", insertion: "\nOven: ___°F · Rack: ___ · Time: ___ min", symbol: "oven"))
        }
        if !text.contains("min") && !text.contains("hour") {
            results.append(.init(title: "Add timing", insertion: "\nCook time: ___ minutes", symbol: "timer"))
        }
        if body.count > 40 {
            results.append(.init(title: "Capture the result", insertion: "\nNext time: ", symbol: "arrow.triangle.2.circlepath"))
        }
        return Array(results.prefix(4))
    }
}

/// Runs the bundled `Cooking Assistant 1` text classifier entirely on-device.
final class CoreMLCookingSuggestionEngine: CookingSuggestionEngine {
    private let fallback = LocalCookingSuggestionEngine()
    private lazy var model: MLModel? = {
        let names = ["Cooking Assistant 1", "Cooking_Assistant_1"]
        guard let url = names.compactMap({ Bundle.main.url(forResource: $0, withExtension: "mlmodelc") }).first else {
            return nil
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        return try? MLModel(contentsOf: url, configuration: configuration)
    }()

    func suggestions(title: String, body: String) async -> [CookingSuggestion] {
        let text = [title, body].filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty,
              let model,
              let input = try? MLDictionaryFeatureProvider(dictionary: ["text": text]),
              let output = try? await model.prediction(from: input),
              let label = output.featureValue(for: "label")?.stringValue,
              let modelSuggestion = Self.suggestion(for: label) else {
            return await fallback.suggestions(title: title, body: body)
        }

        let analysis = Self.complexAnalysis(for: label, title: title, body: body)
        var results = [
            CookingSuggestion(
                title: "Add full cooking analysis",
                insertion: analysis,
                symbol: "text.badge.checkmark"
            ),
            modelSuggestion
        ]
        let ruleSuggestions = await fallback.suggestions(title: title, body: body)
        results.append(contentsOf: ruleSuggestions.filter { $0.title != modelSuggestion.title })
        return Array(results.prefix(4))
    }

    private static func complexAnalysis(for label: String, title: String, body: String) -> String {
        let guidance: [String: (focus: String, why: String, steps: [String], check: String)] = [
            "seasoning_balance": ("seasoning balance", "A good result depends on salt, sweetness, acidity, heat, and richness supporting one another.", ["Taste before changing anything and name the dominant flavor.", "Adjust only one element in a small increment.", "Wait, stir, and taste again before the next adjustment."], "The dish should taste complete without any single seasoning calling attention to itself."),
            "sweetness": ("sweetness", "Sweetness can soften acid and bitterness, but excess sweetness quickly hides the main ingredients.", ["Identify whether the sweetness comes from sugar, caramelization, or the ingredients themselves.", "Add sweetness in very small increments.", "Restore contrast with salt or acid if the flavor becomes flat."], "The first impression should still be the main ingredient, not sugar."),
            "browning": ("browning", "Browning builds roasted flavor through high surface heat and low surface moisture.", ["Dry the food and preheat the cooking surface.", "Leave space between pieces so steam can escape.", "Let a crust form before turning or stirring."], "Look for an even golden-to-deep-brown surface without scorched aromas."),
            "richness": ("richness", "Fat carries aroma and creates body, while acid and fresh flavors keep richness from feeling heavy.", ["Add fat gradually and emulsify it into the dish.", "Taste for weight and coating on the palate.", "Finish with acid, herbs, or a fresh garnish for contrast."], "The finish should feel rounded rather than greasy or tiring."),
            "herbs_spices": ("herbs and spices", "Timing determines whether aromatics taste deep, toasted, fresh, or bitter.", ["Bloom sturdy dried spices briefly in fat.", "Layer sturdy herbs during cooking.", "Add delicate herbs and ground spices near the finish."], "Each aromatic should support the dish while remaining recognizable."),
            "texture": ("texture", "Texture improves when the desired contrast is defined before changing the cooking method.", ["Write down the target: crisp, tender, creamy, chewy, or flaky.", "Change heat, moisture, or cooking time to move toward that target.", "Preserve contrast by adding crisp garnishes at serving time."], "Test the center and surface separately; both should match the intended result."),
            "umami": ("savory depth", "Umami ingredients add persistence and depth, but concentrated sources can also add salt.", ["Choose one compatible source such as mushrooms, tomato, aged cheese, miso, or soy.", "Add a small amount early enough to integrate.", "Retaste for salt before adding any more seasoning."], "The dish should taste deeper, not distinctly like the added ingredient."),
            "sauce_quality": ("sauce quality", "A finished sauce needs the right consistency, seasoning, and connection to the main ingredient.", ["Reduce or loosen until the sauce coats the food cleanly.", "Balance salt, acid, sweetness, and richness.", "Finish off heat with butter, oil, herbs, or reserved cooking liquid if appropriate."], "The sauce should cling lightly and leave a clean path when a spoon crosses the pan."),
            "doneness": ("doneness", "Time is only an estimate; temperature, carryover cooking, and visual cues give a repeatable result.", ["Set a target internal temperature or texture before cooking.", "Measure at the thickest point without touching bone or the pan.", "Remove slightly early and allow for carryover cooking while resting."], "Record both the measured temperature and the final texture for the next attempt."),
            "moisture": ("moisture", "Moisture loss is controlled by surface exposure, temperature, cooking time, and resting.", ["Use the gentlest heat that still produces the desired exterior.", "Cover, baste, or add liquid when the method allows it.", "Rest proteins before slicing and baked goods before judging texture."], "The center should remain juicy or tender without unwanted liquid pooling."),
            "aromatics": ("aromatics", "Onion, garlic, ginger, and spices need enough heat to release aroma without burning.", ["Cut aromatics evenly so they cook at the same rate.", "Start sturdy aromatics first and add garlic later.", "Cook until fragrant, then cool the pan with the next ingredient before scorching begins."], "The aroma should be rounded and fragrant, never raw or acrid."),
            "substitution": ("ingredient substitution", "A reliable substitute matches the original ingredient’s function, not only its flavor.", ["Identify whether the ingredient supplies fat, water, structure, acidity, sweetness, or aroma.", "Choose a replacement with the closest functional properties.", "Adjust liquid, seasoning, and cooking time, then document the ratio used."], "Judge flavor and structure separately before deciding whether the substitution worked."),
            "acidity": ("acidity", "Acid brightens flavors and cuts richness, but its effect grows quickly near the finish.", ["Taste the dish at serving temperature.", "Add lemon, vinegar, wine, or another compatible acid a few drops at a time.", "Stir thoroughly and retaste after each addition."], "Flavors should become clearer and more vivid without tasting sharply sour."),
            "baking_quality": ("baking consistency", "Baking is sensitive to ratios, temperature, mixing, pan choice, and visual doneness cues.", ["Record ingredient weights and avoid unplanned ratio changes.", "Note oven temperature, rack position, pan material, and bake time.", "Use visual and internal cues rather than time alone to judge doneness."], "Record rise, browning, crumb, and moisture only after the bake has cooled appropriately."),
            "bitterness": ("bitterness", "Bitterness may come from scorching, concentrated peel or spices, or an ingredient’s natural character.", ["Identify and remove any burnt component if possible.", "Dilute concentrated bitterness before adding more seasoning.", "Balance cautiously with salt, fat, sweetness, or acid depending on the dish."], "The pleasant complexity should remain while the harsh aftertaste disappears."),
            "adjustment": ("controlled iteration", "Changing one variable at a time makes the next cooking test useful and repeatable.", ["Name the single biggest problem in the current result.", "Choose one measurable change in time, temperature, ratio, or technique.", "Keep the remaining variables constant and record the outcome."], "The next note should make it clear whether that one change improved the dish.")
        ]

        guard let advice = guidance[label.lowercased()] else { return modelSuggestionText(title: title) }
        let hasTime = body.localizedCaseInsensitiveContains("min") || body.localizedCaseInsensitiveContains("hour")
        let hasTemperature = body.contains("°") || body.localizedCaseInsensitiveContains("temperature")
        var missing: [String] = []
        if !hasTime { missing.append("a precise cooking time") }
        if !hasTemperature { missing.append("a heat or temperature target") }
        if body.count < 80 { missing.append("observable doneness cues") }
        let missingText = missing.isEmpty ? "The note has useful process detail; preserve the exact measurements that worked." : "For repeatability, add " + missing.joined(separator: ", ") + "."

        let steps = advice.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let dish = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "this dish" : title
        return """

        AI cooking analysis — \(dish)
        Focus: \(advice.focus.capitalized)

        Why this matters
        \(advice.why)

        Recommended next steps
        \(steps)

        What to check
        \(advice.check)

        Note quality
        \(missingText)
        """
    }

    private static func modelSuggestionText(title: String) -> String {
        "\nAI cooking analysis\nReview \(title.isEmpty ? "the dish" : title), change one variable, and record the result."
    }

    private static func suggestion(for label: String) -> CookingSuggestion? {
        let values: [String: (String, String, String)] = [
            "seasoning_balance": ("Balance the seasoning", "\nTaste for salt, sweetness, acidity, and heat; adjust gradually.", "scale.3d"),
            "sweetness": ("Check the sweetness", "\nSweetness adjustment: add a small amount, taste, then reassess.", "cube"),
            "browning": ("Build more browning", "\nFor deeper browning: dry the surface, preheat the pan, and avoid crowding.", "flame"),
            "richness": ("Round out the richness", "\nRichness adjustment: finish with a little fat, then balance with acid.", "drop.fill"),
            "herbs_spices": ("Refine herbs and spices", "\nHerbs/spices: bloom dried spices early; add delicate herbs near the end.", "leaf"),
            "texture": ("Improve the texture", "\nTexture goal: ___ · Change next time: ___", "circle.grid.cross"),
            "umami": ("Boost savory depth", "\nUmami option: add mushrooms, tomato, aged cheese, miso, or soy sparingly.", "sparkles"),
            "sauce_quality": ("Tune the sauce", "\nSauce check: consistency ___ · seasoning ___ · finish ___", "water.waves"),
            "doneness": ("Record doneness", "\nDoneness target: ___ · Internal temperature: ___°F", "thermometer.medium"),
            "moisture": ("Protect moisture", "\nMoisture note: reduce cooking time, cover, baste, or rest before slicing.", "humidity"),
            "aromatics": ("Strengthen the aromatics", "\nAromatics: cook onion/garlic/spices until fragrant before adding liquids.", "wind"),
            "substitution": ("Plan a substitution", "\nSubstitution: replace ___ with ___; adjust liquid, fat, or cooking time as needed.", "arrow.left.arrow.right"),
            "acidity": ("Brighten with acidity", "\nAcidity adjustment: add lemon, vinegar, or another acid a little at a time.", "drop.triangle"),
            "baking_quality": ("Log the bake", "\nBake: ___°F · Rack: ___ · Time: ___ min · Visual cue: ___", "oven"),
            "bitterness": ("Tame bitterness", "\nBitterness adjustment: balance with salt, fat, sweetness, or dilution.", "mouth"),
            "adjustment": ("Capture an adjustment", "\nNext test: change ___ from ___ to ___, keeping everything else constant.", "slider.horizontal.3")
        ]
        guard let value = values[label.lowercased()] else { return nil }
        return CookingSuggestion(title: value.0, insertion: value.1, symbol: value.2)
    }
}
