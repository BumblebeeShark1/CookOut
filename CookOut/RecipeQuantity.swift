import Foundation

/// Quantities are scaled only at the start of an ingredient. Package sizes,
/// preparation notes, directions, and cooking temperatures stay as written.
enum RecipeQuantity {
    private static let vulgar: [Character: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75, "⅐": 1.0 / 7, "⅑": 1.0 / 9, "⅒": 0.1, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8, "⅙": 1.0 / 6, "⅚": 5.0 / 6, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875]
    private static let token = #"(?:\d+\s+\d+\s*/\s*\d+|\d*\s*[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞]|\d+\s*/\s*\d+|\d+(?:\.\d+)?|\.\d+)"#
    private static let pattern = try! NSRegularExpression(pattern: "^(" + token + ")(?:([ \\t]*(?:[-–—]|to)[ \\t]*)(" + token + "))?")

    static func ingredientLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[-•*]\s+"#, with: "", options: .regularExpression)
        }.filter { !$0.isEmpty }
    }

    static func directionLines(_ text: String) -> [String] {
        ingredientLines(text).map {
            $0.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression)
        }.filter { !$0.isEmpty }
    }

    static func canScale(_ ingredient: String) -> Bool { parse(ingredient) != nil }

    static func leadingQuantity(in ingredient: String) -> (quantity: Double, suffix: String)? {
        guard let parsed = parse(ingredient), parsed.second == nil else { return nil }
        return (parsed.first, parsed.suffix.trimmingCharacters(in: .whitespaces))
    }

    static func scale(_ ingredient: String, by multiplier: Double) -> String {
        guard multiplier.isFinite, multiplier > 0, multiplier <= 1000,
              multiplier != 1, let parsed = parse(ingredient) else { return ingredient }
        let first = parsed.first * multiplier
        let second = parsed.second.map { $0 * multiplier }
        guard first.isFinite, first <= 1_000_000_000,
              second == nil || (second!.isFinite && second! <= 1_000_000_000) else { return ingredient }
        return format(first) + (second.map { parsed.separator + format($0) } ?? "") + parsed.suffix
    }

    static func format(_ value: Double) -> String {
        guard value.isFinite, value >= 0, value <= 1_000_000_000 else { return "—" }
        let whole = floor(value)
        let fractions: [(Double, String)] = [(0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"), (0.375, "⅜"), (0.5, "½"), (0.625, "⅝"), (2.0 / 3, "⅔"), (0.75, "¾"), (0.875, "⅞")]
        let remainder = value - whole
        if let fraction = fractions.first(where: { abs(remainder - $0.0) < 0.000001 }) {
            return (whole > 0 ? String(Int(whole)) + " " : "") + fraction.1
        }
        // Avoid turning a small but nonzero amount into zero.
        if value > 0, value < 0.000001 { return String(value) }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func convertMeasurements(in text: String, to system: RecipeMeasurementSystem) -> String {
        guard system != .original, text.count <= 100_000 else { return text }
        let units = #"(?:imperial\s+(?:fluid\s+ounces?|fl\.?\s*oz|pints?)|UK\s+(?:imperial\s+)?(?:fluid\s+ounces?|fl\.?\s*oz|pints?)|US\s+(?:fluid\s+ounces?|fl\.?\s*oz|cups?|tablespoons?|tbsp|teaspoons?|tsp|pints?)|fluid\s+ounces?|fl\.?\s*oz|kilograms?|kg|milligrams?|mg|grams?|g|millilit(?:er|re)s?|ml|lit(?:er|re)s?|l|pounds?|lbs?|ounces?|oz|tablespoons?|tbsp|teaspoons?|tsp|cups?|pints?|[℃℉]|°\s*[CF]|degrees?\s+(?:Celsius|Fahrenheit)|Celsius|Fahrenheit)"#
        guard let expression = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}./+–—-])([+-]?"# + token + #")(?:(\s*(?:[-–—]|to)\s*)([+-]?"# + token + #"))?\s*("# + units + #")(?![\p{L}\p{N}])"#, options: [.caseInsensitive]) else { return text }
        var output = text
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let quantityRange = Range(match.range(at: 1), in: text), let quantity = number(String(text[quantityRange])),
                  let unitRange = Range(match.range(at: 4), in: text), Range(match.range, in: text) != nil,
                  let source = measurementUnit(String(text[unitRange])) else { continue }
            var second: Double?
            if let secondRange = Range(match.range(at: 3), in: text) {
                guard let value = number(String(text[secondRange])), value >= quantity else { continue }
                second = value
            }
            let target = convertedUnit(for: source.unit, amount: quantity * source.factor, system: system)
            guard let first = KitchenUnit.convert(quantity * source.factor, from: source.unit, to: target) else { continue }
            var converted = measurementNumber(first)
            if let second {
                guard let value = KitchenUnit.convert(second * source.factor, from: source.unit, to: target), let separatorRange = Range(match.range(at: 2), in: text) else { continue }
                converted += String(text[separatorRange]) + measurementNumber(value)
            }
            // Recompute String indices after each replacement; matches are applied
            // backwards so original UTF-16 offsets before it remain valid.
            guard let outputRange = Range(match.range, in: output) else { continue }
            output.replaceSubrange(outputRange, with: converted + " " + target.recipeSymbol)
        }
        return output
    }

    private static func measurementNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.usesSignificantDigits = true
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 4
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func measurementUnit(_ text: String) -> (unit: KitchenUnit, factor: Double)? {
        let unit = text.lowercased().replacingOccurrences(of: ".", with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if unit == "℃" || unit.contains("celsius") || unit.replacingOccurrences(of: " ", with: "") == "°c" { return (.celsius, 1) }
        if unit == "℉" || unit.contains("fahrenheit") || unit.replacingOccurrences(of: " ", with: "") == "°f" { return (.fahrenheit, 1) }
        if unit.hasPrefix("uk ") || unit.hasPrefix("imperial ") { return (unit.contains("pint") ? .imperialPints : .imperialOunces, 1) }
        let plain = unit.hasPrefix("us ") ? String(unit.dropFirst(3)) : unit
        if plain.contains("fluid") || plain.hasPrefix("fl") { return (.usOunces, 1) }
        switch plain {
        case "kg", "kilogram", "kilograms": return (.kilograms, 1)
        case "mg", "milligram", "milligrams": return (.grams, 0.001)
        case "g", "gram", "grams": return (.grams, 1)
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres": return (.millilitres, 1)
        case "l", "liter", "liters", "litre", "litres": return (.litres, 1)
        case "lb", "lbs", "pound", "pounds": return (.pounds, 1)
        case "oz", "ounce", "ounces": return (.ounces, 1)
        case "tsp", "teaspoon", "teaspoons": return (.teaspoons, 1)
        case "tbsp", "tablespoon", "tablespoons": return (.tablespoons, 1)
        case "cup", "cups": return (.cups, 1)
        case "pint", "pints": return (.usPints, 1)
        default: return nil
        }
    }

    private static func convertedUnit(for source: KitchenUnit, amount: Double, system: RecipeMeasurementSystem) -> KitchenUnit {
        switch source.dimension {
        case .temperature: return system == .metric ? .celsius : .fahrenheit
        case .weight:
            let grams = KitchenUnit.convert(amount, from: source, to: .grams) ?? 0
            if system == .metric { return grams >= 1000 ? .kilograms : .grams }
            return grams >= 453.59237 ? .pounds : .ounces
        case .volume:
            let millilitres = KitchenUnit.convert(amount, from: source, to: .millilitres) ?? 0
            if system == .metric { return millilitres >= 1000 ? .litres : .millilitres }
            if system == .ukImperial { return millilitres >= 568.26125 ? .imperialPints : .imperialOunces }
            if millilitres >= 59.147059125 { return .cups }
            return millilitres >= 14.78676478125 ? .tablespoons : .teaspoons
        }
    }

    private static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, let fraction = vulgar[last] {
            let prefix = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            guard prefix.isEmpty || Double(prefix) != nil else { return nil }
            return (Double(prefix) ?? 0) + fraction
        }
        if trimmed.contains("/") {
            let parts = trimmed.components(separatedBy: "/")
            guard parts.count == 2, let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)), denominator > 0 else { return nil }
            let left = parts[0].split(whereSeparator: \.isWhitespace)
            guard (1...2).contains(left.count), let numerator = Double(left.last!) else { return nil }
            let whole = left.count == 2 ? Double(left[0]) : 0
            guard let whole else { return nil }
            return whole + numerator / denominator
        }
        return Double(trimmed)
    }

    private static func parse(_ text: String) -> (first: Double, second: Double?, separator: String, suffix: String)? {
        guard text.count <= 10_000, let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let firstRange = Range(match.range(at: 1), in: text), let first = number(String(text[firstRange])),
              first.isFinite, first >= 0, first <= 1_000_000_000,
              let fullRange = Range(match.range, in: text) else { return nil }
        let suffix = String(text[fullRange.upperBound...])
        // Don't partially interpret malformed fractions, decimals, or ranges.
        if let leading = suffix.first, !leading.isWhitespace, !suffix.isEmpty {
            guard suffix.range(of: #"^(?:kg|mg|g|mL|ml|L|l|oz|lbs?|tsp|tbsp)\b"#, options: .regularExpression) != nil else { return nil }
        }
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespaces)
        if trimmedSuffix == "to" || trimmedSuffix.range(of: #"^\d+\s*/"#, options: .regularExpression) != nil { return nil }
        if trimmedSuffix.hasPrefix("/") || trimmedSuffix.hasPrefix(".") || trimmedSuffix.hasPrefix("-") || trimmedSuffix.hasPrefix("–") || trimmedSuffix.hasPrefix("—") || trimmedSuffix.hasPrefix("to ") { return nil }
        var second: Double?
        var separator = ""
        if let range = Range(match.range(at: 3), in: text) {
            guard let value = number(String(text[range])), value.isFinite, value >= first, value <= 1_000_000_000,
                  let separatorRange = Range(match.range(at: 2), in: text) else { return nil }
            second = value
            separator = String(text[separatorRange])
        }
        return (first, second, separator, suffix)
    }
}

enum KitchenDimension: String, CaseIterable, Identifiable {
    case weight = "Weight", volume = "Volume", temperature = "Temperature"
    var id: Self { self }
    var units: [KitchenUnit] { KitchenUnit.allCases.filter { $0.dimension == self } }
}

enum KitchenUnit: String, CaseIterable, Identifiable {
    case grams = "Grams (g)", kilograms = "Kilograms (kg)", ounces = "Ounces (oz)", pounds = "Pounds (lb)"
    case millilitres = "Millilitres (mL)", litres = "Litres (L)", teaspoons = "US teaspoons", tablespoons = "US tablespoons", cups = "US cups", usOunces = "US fluid ounces", usPints = "US pints", imperialOunces = "UK imperial fluid ounces", imperialPints = "UK imperial pints"
    case celsius = "Celsius (°C)", fahrenheit = "Fahrenheit (°F)"
    var id: Self { self }
    var dimension: KitchenDimension {
        switch self {
        case .grams, .kilograms, .ounces, .pounds: .weight
        case .celsius, .fahrenheit: .temperature
        default: .volume
        }
    }
    // Exact definitions in grams and millilitres. US customary and UK imperial
    // volume measures are deliberately distinct. No density assumptions.
    private var baseFactor: Double {
        switch self {
        case .grams: 1
        case .kilograms: 1000
        case .ounces: 28.349523125
        case .pounds: 453.59237
        case .millilitres: 1
        case .litres: 1000
        case .teaspoons: 4.92892159375
        case .tablespoons: 14.78676478125
        case .cups: 236.5882365
        case .usOunces: 29.5735295625
        case .usPints: 473.176473
        case .imperialOunces: 28.4130625
        case .imperialPints: 568.26125
        case .celsius, .fahrenheit: 1
        }
    }
    static func convert(_ value: Double, from: Self, to: Self) -> Double? {
        guard value.isFinite, abs(value) <= 1e12, from.dimension == to.dimension else { return nil }
        if from.dimension == .temperature {
            let celsius = from == .celsius ? value : (value - 32) / 1.8
            guard celsius >= -273.15 - 1e-10 else { return nil }
            return to == .celsius ? celsius : celsius * 1.8 + 32
        }
        guard value >= 0 else { return nil }
        let result = value * from.baseFactor / to.baseFactor
        return result.isFinite ? result : nil
    }
}


enum RecipeMeasurementSystem: String, CaseIterable, Identifiable {
    case original = "As written", metric = "Metric", usCustomary = "Imperial (US)", ukImperial = "Imperial (UK)"
    var id: Self { self }
}

extension KitchenUnit {
    var recipeSymbol: String {
        switch self {
        case .grams: "g"
        case .kilograms: "kg"
        case .ounces: "oz"
        case .pounds: "lb"
        case .millilitres: "mL"
        case .litres: "L"
        case .teaspoons: "US tsp"
        case .tablespoons: "US tbsp"
        case .cups: "US cups"
        case .usOunces: "US fl oz"
        case .usPints: "US pints"
        case .imperialOunces: "UK fl oz"
        case .imperialPints: "UK pints"
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }
}
