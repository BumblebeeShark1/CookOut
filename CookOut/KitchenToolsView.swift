import SwiftUI

struct KitchenToolsView: View {
    let recipes: [CookingNote]
    @State private var recipeID: UUID?
    @State private var servings: Double = 2
    @State private var dimension: KitchenDimension = .weight
    @State private var from: KitchenUnit = .grams
    @State private var to: KitchenUnit = .ounces
    @State private var amount = "100"
    @State private var recipeUnits: RecipeMeasurementSystem = .original

    private var selected: CookingNote? { recipes.first { $0.id == recipeID } }
    private var input: Double? { Double(amount.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var converted: Double? { input.flatMap { KitchenUnit.convert($0, from: from, to: to) } }

    var body: some View {
        NavigationStack {
            CookOutScreen {
                CookOutPageHeader(eyebrow: "A little kitchen arithmetic", title: "Make it your portion.", subtitle: "Scale a favorite recipe, or translate a measurement before you cook.")
                CookOutPanel(title: "Recipe portions", subtitle: "Half for a quiet evening. Double for a full table.", symbol: "person.2") {
                    if recipes.isEmpty {
                        Text("Add a recipe to your library to start scaling.").foregroundStyle(.secondary)
                    } else {
                        Picker("Recipe", selection: $recipeID) {
                            Text("Choose a recipe").tag(nil as UUID?)
                            ForEach(recipes) { recipe in Text(recipe.title.isEmpty ? "Untitled recipe" : recipe.title).tag(Optional(recipe.id)) }
                        }
                        if let selected {
                            RecipePortionControls(originalServings: selected.servings, servings: $servings)
                            RecipeConversionControls(system: $recipeUnits)
                            ScaledIngredientList(note: selected, servings: servings, units: recipeUnits)
                            if !selected.steps.isEmpty {
                                Divider()
                                Text("Directions").font(CookOutTypography.display(24, relativeTo: .title2))
                                ForEach(Array(selected.steps.enumerated()), id: \.offset) { index, step in
                                    Text("\(index + 1). " + RecipeQuantity.convertMeasurements(in: step, to: recipeUnits)).textSelection(.enabled)
                                }
                            }
                            if !selected.body.isEmpty {
                                Divider()
                                Text("Chef’s notes").font(CookOutTypography.display(24, relativeTo: .title2))
                                Text(RecipeQuantity.convertMeasurements(in: selected.body, to: recipeUnits)).textSelection(.enabled)
                            }
                        }
                    }
                }
                CookOutPanel(title: "Metric & imperial", subtitle: "Weight, volume, and oven temperatures—in either direction.", symbol: "arrow.left.arrow.right") {
                    Picker("Measurement", selection: $dimension) {
                        ForEach(KitchenDimension.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) { source; target }
                        VStack(alignment: .leading, spacing: 20) { source; target }
                    }
                    HStack {
                        Button("Swap units", systemImage: "arrow.triangle.swap") {
                            if let converted { amount = String(converted) }
                            let old = from; from = to; to = old
                        }.buttonStyle(.bordered)
                        Spacer()
                    }
                    if converted == nil {
                        Text(dimension == .temperature ? "Enter a temperature at or above absolute zero, using a decimal point." : "Enter a positive number or zero, using a decimal point.")
                            .font(.subheadline).foregroundStyle(CookOutTheme.coral)
                    }
                    Text("US cups and spoons use US customary measures. UK imperial volumes are labeled separately. Weight and volume need an ingredient’s density to convert between them.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Kitchen tools")
        }
        .onChange(of: recipeID) { _, _ in servings = Double(max(1, selected?.servings ?? 2)) }
        .onChange(of: dimension) { _, value in
            switch value {
            case .weight: from = .grams; to = .ounces; amount = "100"
            case .volume: from = .millilitres; to = .cups; amount = "250"
            case .temperature: from = .celsius; to = .fahrenheit; amount = "180"
            }
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FROM").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
            TextField("Amount", text: $amount).cookOutField().accessibilityLabel("Conversion amount")
            Picker("From unit", selection: $from) { ForEach(dimension.units) { Text($0.rawValue).tag($0) } }
        }.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
    }
    private var target: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TO").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
            Text(converted.map { $0.formatted(.number.precision(.significantDigits(1...8))) } ?? "—")
                .font(CookOutTypography.display(30, relativeTo: .title))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                .accessibilityLabel("Converted amount")
                .accessibilityValue(converted.map { $0.formatted(.number.precision(.significantDigits(1...8))) + " " + to.rawValue } ?? "Invalid amount")
            Picker("To unit", selection: $to) { ForEach(dimension.units) { Text($0.rawValue).tag($0) } }
        }.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
    }
}

struct RecipePortionControls: View {
    let originalServings: Int
    @Binding var servings: Double
    private var base: Double { Double(max(1, originalServings)) }
    private var valid: Bool { servings.isFinite && (0.25...1000).contains(servings) && servings / base <= 1000 }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { portionButtons; Spacer(); servingsField }
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) { portionButtons }
                    servingsField
                }
            }
            if valid {
                Text("Originally serves \(originalServings) · \(RecipeQuantity.format(servings / base))× the recipe")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Choose between ¼ and 1,000 servings.").font(.caption).foregroundStyle(CookOutTheme.coral)
            }
        }
    }
    private var portionButtons: some View {
        HStack(spacing: 8) {
            Button("½ Half") { servings = base * 0.5 }
            Button("1× Original") { servings = base }
            Button("2× Double") { servings = min(1000, base * 2) }
        }.buttonStyle(.bordered)
    }
    private var servingsField: some View {
        HStack(spacing: 8) {
            Text("Servings").font(.subheadline)
            TextField("Servings", value: $servings, format: .number).cookOutField().frame(width: 95)
                .accessibilityLabel("Target servings")
        }
    }
}

struct ScaledIngredientList: View {
    let note: CookingNote
    let servings: Double
    var units: RecipeMeasurementSystem = .original
    private var factor: Double { servings / Double(max(1, note.servings)) }
    private var valid: Bool { servings.isFinite && (0.25...1000).contains(servings) && factor <= 1000 }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if note.ingredients.isEmpty { Text("This recipe has no ingredients yet.").foregroundStyle(.secondary) }
            else {
                ForEach(Array(note.ingredients.enumerated()), id: \.offset) { _, ingredient in
                    Text(RecipeQuantity.convertMeasurements(in: valid ? RecipeQuantity.scale(ingredient, by: factor) : ingredient, to: units)).textSelection(.enabled)
                }
                Text("Quantities at the start of each ingredient are scaled. ‘To taste’ and unrecognized quantities stay as written. Adjust seasoning and cooking time as needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Your saved recipe stays unchanged.").font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct RecipeConversionControls: View {
    @Binding var system: RecipeMeasurementSystem
    @State private var imperialConvention: RecipeMeasurementSystem = .usCustomary
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Convert the entire recipe").font(.subheadline.weight(.medium))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button("Convert to metric", systemImage: "arrow.left.arrow.right") { system = .metric }
                        .tint(system == .metric ? CookOutTheme.olive : .secondary)
                    Button("Convert to imperial", systemImage: "arrow.left.arrow.right") { system = imperialConvention }
                        .tint(system == .usCustomary || system == .ukImperial ? CookOutTheme.olive : .secondary)
                    Button("Original units") { system = .original }
                }.buttonStyle(.bordered)
            }
            Picker("Imperial volumes", selection: $imperialConvention) {
                Text("US customary").tag(RecipeMeasurementSystem.usCustomary)
                Text("UK imperial").tag(RecipeMeasurementSystem.ukImperial)
            }.frame(maxWidth: 300, alignment: .leading)
            Text("\(system.rawValue) · Ingredients, package sizes, and temperatures in directions and notes. Converted amounts are rounded; unrecognized measurements stay as written. Unlabeled cups, spoons, fluid ounces, and pints use US measures.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
